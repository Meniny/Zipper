
import Foundation

/// The default chunk size when reading entry data from an archive.
public let defaultReadChunkSize: UInt32 = 16*1024
/// The default chunk size when writing entry data to an archive.
public let defaultWriteChunkSize = defaultReadChunkSize
/// The default permissions for newly added entries.
public let defaultPermissions:UInt16 = 0o755
let defaultPOSIXBufferSize = defaultReadChunkSize
let minDirectoryEndOffset = 22
let maxDirectoryEndOffset = 66000
let endOfCentralDirectoryStructSignature = 0x06054b50
let localFileHeaderStructSignature = 0x04034b50
let dataDescriptorStructSignature = 0x08074b50
let centralDirectoryStructSignature = 0x02014b50

/// The compression method of an `Zipper.Entry` in a ZIP `Zipper`.
public enum CompressionMethod: UInt16 {
    /// Indicates that an `Zipper.Entry` has no compression applied to its contents.
    case none = 0
    /// Indicates that contents of an `Zipper.Entry` have been compressed with a zlib compatible Deflate algorithm.
    case deflate = 8
}

/// A sequence of uncompressed or compressed ZIP entries.
///
/// You use an `Zipper` to create, read or update ZIP files.
/// To read an existing ZIP file, you have to pass in an existing file `URL` and `AccessMode.read`:
///
///     var archiveURL = URL(fileURLWithPath: "/path/file.zip")
///     var archive = Zipper(url: archiveURL, accessMode: .read)
///
/// An `Zipper` is a sequence of entries. You can
/// iterate over an archive using a `for`-`in` loop to get access to individual `Zipper.Entry` objects:
///
///     for entry in archive {
///         print(entry.path)
///     }
///
/// Each `Zipper.Entry` in an `Zipper` is represented by its `path`. You can
/// use `path` to retrieve the corresponding `Zipper.Entry` from an `Zipper` via subscripting:
///
///     let entry = archive['/path/file.txt']
///
/// To create a new `Zipper`, pass in a non-existing file URL and `AccessMode.create`. To modify an
/// existing `Zipper` use `AccessMode.update`:
///
///     var archiveURL = URL(fileURLWithPath: "/path/file.zip")
///     var archive = Zipper(url: archiveURL, accessMode: .update)
///     try archive?.addEntry("test.txt", relativeTo: baseURL, compressionMethod: .deflate)
public final class Zipper: Sequence {
    typealias LocalFileHeader = Zipper.Entry.LocalFileHeader
    typealias DataDescriptor = Zipper.Entry.DataDescriptor
    typealias CentralDirectoryStructure = Zipper.Entry.CentralDirectoryStructure

    /// An error that occurs during reading, creating or updating a ZIP file.
    public enum ArchiveError: Error {
        /// Thrown when an archive file is either damaged or inaccessible.
        case unreadableArchive
        /// Thrown when an archive is either opened with AccessMode.read or the destination file is unwritable.
        case unwritableArchive
        /// Thrown when the path of an `Zipper.Entry` cannot be stored in an archive.
        case invalidEntryPath
        /// Thrown when an `Zipper.Entry` can't be stored in the archive with the proposed compression method.
        case invalidCompressionMethod
        /// Thrown when the start of the central directory exceeds `UINT32_MAX`
        case invalidStartOfCentralDirectoryOffset
        /// Thrown when an archive does not contain the required End of Central Directory Record.
        case missingEndOfCentralDirectoryRecord
    }

    /// The access mode for an `Zipper`.
    public enum AccessMode: UInt {
        /// Indicates that a newly instantiated `Zipper` should create its backing file.
        case create
        /// Indicates that a newly instantiated `Zipper` should read from an existing backing file.
        case read
        /// Indicates that a newly instantiated `Zipper` should update an existing backing file.
        case update
    }

    struct EndOfCentralDirectoryRecord: ZipperDataSerializable {
        let endOfCentralDirectorySignature = UInt32(endOfCentralDirectoryStructSignature)
        let numberOfDisk: UInt16
        let numberOfDiskStart: UInt16
        let totalNumberOfEntriesOnDisk: UInt16
        let totalNumberOfEntriesInCentralDirectory: UInt16
        let sizeOfCentralDirectory: UInt32
        let offsetToStartOfCentralDirectory: UInt32
        let zipFileCommentLength: UInt16
        let zipFileCommentData: Data
        static let size = 22
    }

    /// URL of an Archive's backing file.
    public let url: URL
    /// Access mode for an archive file.
    public let accessMode: AccessMode
    var archiveFile: UnsafeMutablePointer<FILE>
    var endOfCentralDirectoryRecord: EndOfCentralDirectoryRecord

    /// Initializes a new ZIP `Zipper`.
    ///
    /// You can use this initalizer to create new archive files or to read and update existing ones.
    ///
    /// To read existing ZIP files, pass in an existing file URL and `AccessMode.read`.
    ///
    /// To create a new ZIP file, pass in a non-existing file URL and `AccessMode.create`.
    ///
    /// To update an existing ZIP file, pass in an existing file URL and `AccessMode.update`.
    ///
    /// - Parameters:
    ///   - url: File URL to the receivers backing file.
    ///   - mode: Access mode of the receiver.
    ///
    /// - Returns: An archive initialized with a backing file at the passed in file URL and the given access mode
    ///   or `nil` if the following criteria are not met:
    ///   - The file URL _must_ point to an existing file for `AccessMode.read`
    ///   - The file URL _must_ point to a non-existing file for `AccessMode.write`
    ///   - The file URL _must_ point to an existing file for `AccessMode.update`
    public init?(url: URL, accessMode mode: AccessMode) {
        self.url = url
        self.accessMode = mode
        let fileManager = FileManager()
        switch mode {
        case .read:
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            guard fileManager.isReadableFile(atPath: url.path) else {return nil }
            let fileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: url.path)
            self.archiveFile = fopen(fileSystemRepresentation, "rb")
            guard let endOfCentralDirectoryRecord = Zipper.scanForEndOfCentralDirectoryRecord(in: archiveFile) else {
                return nil
            }
            self.endOfCentralDirectoryRecord = endOfCentralDirectoryRecord
        case .create:
            guard !fileManager.fileExists(atPath: url.path) else { return nil }
            let endOfCentralDirectoryRecord = EndOfCentralDirectoryRecord(numberOfDisk: 0, numberOfDiskStart: 0,
                                                                          totalNumberOfEntriesOnDisk: 0,
                                                                          totalNumberOfEntriesInCentralDirectory: 0,
                                                                          sizeOfCentralDirectory: 0,
                                                                          offsetToStartOfCentralDirectory: 0,
                                                                          zipFileCommentLength: 0,
                                                                          zipFileCommentData: Data())
            guard fileManager.createFile(atPath: url.path, contents: endOfCentralDirectoryRecord.data) else {
                return nil
            }
            fallthrough
        case .update:
            guard fileManager.isWritableFile(atPath: url.path) else {return nil }
            let fileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: url.path)
            self.archiveFile = fopen(fileSystemRepresentation, "rb+")
            guard let endOfCentralDirectoryRecord = Zipper.scanForEndOfCentralDirectoryRecord(in: archiveFile) else {
                return nil
            }
            self.endOfCentralDirectoryRecord = endOfCentralDirectoryRecord
            fseek(self.archiveFile, 0, SEEK_SET)
        }
        setvbuf(self.archiveFile, nil, _IOFBF, Int(defaultPOSIXBufferSize))
    }

    deinit {
        fclose(self.archiveFile)
    }

    public func makeIterator() -> AnyIterator<Zipper.Entry> {
        let endOfCentralDirectoryRecord = self.endOfCentralDirectoryRecord
        var directoryIndex = Int(endOfCentralDirectoryRecord.offsetToStartOfCentralDirectory)
        var i = 0
        return AnyIterator {
            guard i < Int(endOfCentralDirectoryRecord.totalNumberOfEntriesInCentralDirectory) else { return nil }
            guard let centralDirStruct: CentralDirectoryStructure = Data.readStructure(from: self.archiveFile,
                                                                                             at: directoryIndex) else {
                                                                                                return nil
            }
            let offset = Int(centralDirStruct.relativeOffsetOfLocalHeader)
            guard let localFileHeader: LocalFileHeader = Data.readStructure(from: self.archiveFile,
                                                                            at: offset) else { return nil }
            var dataDescriptor: DataDescriptor? = nil
            if centralDirStruct.usesDataDescriptor {
                let additionalSize = Int(localFileHeader.fileNameLength + localFileHeader.extraFieldLength)
                let isCompressed = centralDirStruct.compressionMethod != CompressionMethod.none.rawValue
                let dataSize = isCompressed ? centralDirStruct.compressedSize : centralDirStruct.uncompressedSize
                let descriptorPosition = offset + LocalFileHeader.size + additionalSize + Int(dataSize)
                dataDescriptor = Data.readStructure(from: self.archiveFile, at: descriptorPosition)
            }
            defer {
                directoryIndex += CentralDirectoryStructure.size
                directoryIndex += Int(centralDirStruct.fileNameLength)
                directoryIndex += Int(centralDirStruct.extraFieldLength)
                directoryIndex += Int(centralDirStruct.fileCommentLength)
                i += 1
            }
            return Zipper.Entry(centralDirectoryStructure: centralDirStruct,
                         localFileHeader: localFileHeader, dataDescriptor: dataDescriptor)
        }
    }

    /// Retrieve the ZIP `Zipper.Entry` with the given `path` from the receiver.
    ///
    /// - Note: The ZIP file format specification does not enforce unique paths for entries.
    ///   Therefore an archive can contain multiple entries with the same path. This method
    ///   always returns the first `Zipper.Entry` with the given `path`.
    ///
    /// - Parameter path: A relative file path identifiying the corresponding `Zipper.Entry`.
    /// - Returns: An `Zipper.Entry` with the given `path`. Otherwise, `nil`.
    public subscript(path: String) -> Zipper.Entry? {
        return self.filter { $0.path == path }.first
    }

    // MARK: - Helpers

    private static func scanForEndOfCentralDirectoryRecord(in file: UnsafeMutablePointer<FILE>)
        -> EndOfCentralDirectoryRecord? {
        var directoryEnd = 0
        var i = minDirectoryEndOffset
        var fileStat = stat()
        fstat(fileno(file), &fileStat)
        let archiveLength = Int(fileStat.st_size)
        while directoryEnd == 0 && i < maxDirectoryEndOffset && i <= archiveLength {
            fseek(file, archiveLength - i, SEEK_SET)
            var potentialDirectoryEndTag: UInt32 = UInt32()
            fread(&potentialDirectoryEndTag, 1, MemoryLayout<UInt32>.size, file)
            if potentialDirectoryEndTag == UInt32(endOfCentralDirectoryStructSignature) {
                directoryEnd = archiveLength - i
                return Data.readStructure(from: file, at: directoryEnd)
            }
            i += 1
        }
        return nil
    }
}

extension Zipper.EndOfCentralDirectoryRecord {
    var data: Data {
        var endOfCentralDirectorySignature = self.endOfCentralDirectorySignature
        var numberOfDisk = self.numberOfDisk
        var numberOfDiskStart = self.numberOfDiskStart
        var totalNumberOfEntriesOnDisk = self.totalNumberOfEntriesOnDisk
        var totalNumberOfEntriesInCentralDirectory = self.totalNumberOfEntriesInCentralDirectory
        var sizeOfCentralDirectory = self.sizeOfCentralDirectory
        var offsetToStartOfCentralDirectory = self.offsetToStartOfCentralDirectory
        var zipFileCommentLength = self.zipFileCommentLength
        var data = Data(buffer: UnsafeBufferPointer(start: &endOfCentralDirectorySignature, count: 1))
        data.append(UnsafeBufferPointer(start: &numberOfDisk, count: 1))
        data.append(UnsafeBufferPointer(start: &numberOfDiskStart, count: 1))
        data.append(UnsafeBufferPointer(start: &totalNumberOfEntriesOnDisk, count: 1))
        data.append(UnsafeBufferPointer(start: &totalNumberOfEntriesInCentralDirectory, count: 1))
        data.append(UnsafeBufferPointer(start: &sizeOfCentralDirectory, count: 1))
        data.append(UnsafeBufferPointer(start: &offsetToStartOfCentralDirectory, count: 1))
        data.append(UnsafeBufferPointer(start: &zipFileCommentLength, count: 1))
        data.append(self.zipFileCommentData)
        return data
    }

    init?(data: Data, additionalDataProvider provider: (Int) throws -> Data) {
        guard data.count == Zipper.EndOfCentralDirectoryRecord.size else { return nil }
        guard data.scanValue(start: 0) == endOfCentralDirectorySignature else { return nil }
        self.numberOfDisk = data.scanValue(start: 4)
        self.numberOfDiskStart = data.scanValue(start: 6)
        self.totalNumberOfEntriesOnDisk = data.scanValue(start: 8)
        self.totalNumberOfEntriesInCentralDirectory = data.scanValue(start: 10)
        self.sizeOfCentralDirectory = data.scanValue(start: 12)
        self.offsetToStartOfCentralDirectory = data.scanValue(start: 16)
        self.zipFileCommentLength = data.scanValue(start: 20)
        guard let commentData = try? provider(Int(self.zipFileCommentLength)) else { return nil }
        guard commentData.count == Int(self.zipFileCommentLength) else { return nil }
        self.zipFileCommentData = commentData
    }

    init(record: Zipper.EndOfCentralDirectoryRecord,
         numberOfEntriesOnDisk: UInt16,
         numberOfEntriesInCentralDirectory: UInt16,
         updatedSizeOfCentralDirectory: UInt32,
         startOfCentralDirectory: UInt32) {
        numberOfDisk = record.numberOfDisk
        numberOfDiskStart = record.numberOfDiskStart
        totalNumberOfEntriesOnDisk = numberOfEntriesOnDisk
        totalNumberOfEntriesInCentralDirectory = numberOfEntriesInCentralDirectory
        sizeOfCentralDirectory = updatedSizeOfCentralDirectory
        offsetToStartOfCentralDirectory = startOfCentralDirectory
        zipFileCommentLength = record.zipFileCommentLength
        zipFileCommentData = record.zipFileCommentData
    }
}
