//
//  ZipFileViewer.swift
//  Zip preview
//
//  Created by DucTran on 10/03/2023.
//

import Foundation

public protocol CompletedStructure {
    var path: String { get set }
    var name: String { get }
    var size: String { get set }
}

public class CompletedFileStructure: CompletedStructure {
    var path: String
    var name: String {
        get {
            return  NSString(string: path).lastPathComponent
        }
    }
    var size: String
    init(path: String, size: String) {
        self.path = path
        self.size = size
    }
}

public class CompletedFolderStructure: CompletedStructure {
    var path: String
    var name: String {
        get {
            return  NSString(string: path).lastPathComponent
        }
    }
    var size: String
    var folderContent: [CompletedFolderStructure] = []
    var fileContent: [CompletedFileStructure] = []
    func isFolderContain() -> Bool {
        return false
    }
    
    init(path: String, size: String) {
        self.path = path
        self.size = size
    }
    
    func addChildFile(with file: CompletedFileStructure) -> Bool {
        if file.path.contains(self.path) {
            fileContent.append(file)
            return true
        }
        return false
    }
    
    func addChildFolder(with folder: CompletedFolderStructure) -> Bool{
        if folder.path.contains(self.path) {
            folderContent.append(folder)
            return true
        }
        return false
    }
    
    var addNestedPrint: String = ""
    
    func addNested(string: String) {
        addNestedPrint += "    " + string
    }
    
    var description: String {
        let content = "\\\(name)\n"
        var fileStr = ""
        for i in fileContent {
            fileStr += addNestedPrint + "    file: \(i.name)\n"
        }
        var folderStr = ""
        for i in folderContent {
            i.addNested(string: addNestedPrint)
            folderStr += addNestedPrint + "    \(i.description)\n"
        }
        return content + folderStr + fileStr
    }
}

enum CompressFileError: Error {
    case noSuchZipFile
    case unzipFileInvalid
    case createFileDecompressError
    case cannotReadZipFile
    case cannotZipFile
    case cannotUnzipFile
    case noSuchFileInZip
    
    var localizeDescription: String {
        switch self {
        case .noSuchZipFile:
            return "File zip not exist"
        case .unzipFileInvalid:
            return "File to decompress is not valid type (zip, rar, ...)"
        case .cannotUnzipFile:
            return "Unzipping error"
        case .cannotZipFile:
            return "Zipping error"
        case .createFileDecompressError:
            return "Create file to decompressing error"
        case .cannotReadZipFile:
            return "Cannot read zip file"
        case .noSuchFileInZip:
            return "File zip not contain that file"
        }
    }
}

public final class ZipFileViewer {

    func preSort(on path: URL) throws -> [[CompletedFolderStructure]] {
        let fileManager = FileManager()
        if fileManager.fileExists(atPath: path.path) {
            guard let archive = Zipper(url: path, accessMode: .read) else {
                throw CompressFileError.cannotReadZipFile
            }
            var fileRes: [String: [CompletedFileStructure]] = [:]
            var folderRes: [String: [CompletedFolderStructure]] = [:]
            let iter = archive.createStructure()
            while true {
                if let a = iter.next() {
                    if case .stop = a {
                        break
                    }
                    if case .file(let path, let size) = a {
                        let level = NSString(string: path).pathComponents.count - 1
                        if fileRes.contains(where: { $0.key == String(level)}) {
                            fileRes["\(level)"]?.append(CompletedFileStructure(path: path, size: size))
                        } else {
                            fileRes["\(level)"] = [CompletedFileStructure(path: path, size: size)]
                        }
                    }
                    if case .folder(let path, let size) = a {
                        let level = NSString(string: path).pathComponents.count - 1
                        if folderRes.contains(where: { $0.key == String(level)}) {
                            folderRes["\(level)"]?.append(CompletedFolderStructure(path: path, size: size))
                        } else {
                            folderRes["\(level)"] = [CompletedFolderStructure(path: path, size: size)]
                        }
                    }
                }
            }
            for level in fileRes.keys {
                let folderSameLevel = folderRes[level]!
                for file in fileRes[level]! {
                    for folder in folderSameLevel {
                        if folder.addChildFile(with: file) {
                            break
                        }
                    }
                }
            }
            return folderRes.keys.sorted().map({ key in folderRes[key]! })
        } else {
            throw CompressFileError.noSuchZipFile
        }
    }
    
    
    public func previewStructure(on url: URL) -> [CompletedFolderStructure]? {
        guard let preSort = try? self.preSort(on: url) else { return nil}
        
        for index in 0..<preSort.count - 1 {
            let listCurrentLevel = preSort[index]
            for nextLevel in preSort[index + 1] {
                for currentLevel in listCurrentLevel {
                    if currentLevel.addChildFolder(with: nextLevel) {
                        break
                    }
                }
            }
        }
        return preSort[0]
    }
}


fileprivate enum CompressedFileType {
    case folder(path: String, size: String)
    case file(path: String, size: String)
    case none
    case stop
}

fileprivate extension Zipper {
    
    public enum OSType: UInt {
        case msdos = 0
        case unix = 3
        case osx = 19
        case unused = 20
    }
    
    func getEntryType(centralDirectoryStructure: CentralDirectoryStructure) -> Entry.EntryType {
        let osTypeRaw = centralDirectoryStructure.versionMadeBy >> 8
        let osType = OSType(rawValue: UInt(osTypeRaw)) ?? .unused
        var isDirectory = extractPath(centralDirectoryStructure: centralDirectoryStructure).hasSuffix("/")
        switch osType {
        case .unix, .osx:
            let mode = mode_t(centralDirectoryStructure.externalFileAttributes >> 16) & S_IFMT
            switch mode {
            case S_IFREG:
                return .file
            case S_IFDIR:
                return .directory
            case S_IFLNK:
                return .symlink
            default:
                return .file
            }
        case .msdos:
            isDirectory = isDirectory || ((centralDirectoryStructure.externalFileAttributes >> 4) == 0x01)
            fallthrough
        default:
            //for all other OSes we can only guess based on the directory suffix char
            return isDirectory ? .directory : .file
        }
    }
    
    func extractPath(centralDirectoryStructure: CentralDirectoryStructure) -> String {
        let dosLatinUS = 0x400
        let dosLatinUSEncoding = CFStringEncoding(dosLatinUS)
        let dosLatinUSStringEncoding = CFStringConvertEncodingToNSStringEncoding(dosLatinUSEncoding)
        let codepage437 = String.Encoding(rawValue: dosLatinUSStringEncoding)
        let isUTF8 = ((centralDirectoryStructure.generalPurposeBitFlag >> 11) & 1) != 0
        let encoding = isUTF8 ? String.Encoding.utf8 : codepage437
        return String(data:centralDirectoryStructure.fileNameData, encoding: encoding) ?? ""
    }
    
    func createStructure() ->  AnyIterator<CompressedFileType> {
        let endOfCentralDirectoryRecord = self.endOfCentralDirectoryRecord
        var directoryIndex = Int(endOfCentralDirectoryRecord.offsetToStartOfCentralDirectory)
        var i = 0
        return AnyIterator {
            guard i < Int(endOfCentralDirectoryRecord.totalNumberOfEntriesInCentralDirectory) else { return CompressedFileType.stop }
            guard let centralDirStruct: CentralDirectoryStructure = Data.readStructure(from: self.archiveFile,
                                                                                       at: directoryIndex) else {
                return CompressedFileType.none
            }
            defer {
                directoryIndex += CentralDirectoryStructure.size
                directoryIndex += Int(centralDirStruct.fileNameLength)
                directoryIndex += Int(centralDirStruct.extraFieldLength)
                directoryIndex += Int(centralDirStruct.fileCommentLength)
                i += 1
            }
            let entryType = self.getEntryType(centralDirectoryStructure: centralDirStruct)
            if entryType == .directory {
                let folderPath = self.extractPath(centralDirectoryStructure: centralDirStruct)
                let folderSize = String(centralDirStruct.uncompressedSize)
                return .folder(path: folderPath, size: folderSize)
            } else if entryType == .file {
                let filePath = self.extractPath(centralDirectoryStructure: centralDirStruct)
                let fileSize = String(centralDirStruct.uncompressedSize)
                return .file(path: filePath, size: fileSize)
            } else {
                return CompressedFileType.none
            }
        }
    }
}
