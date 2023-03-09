enum CompressedFileType {
    case folder(path: String, size: String)
    case file(path: String, size: String)
    case none
    case stop
}


extension Zipper {
    
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
    
    public func generateStructure() ->  AnyIterator<CompressedFileType> {
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
                let folderSize = centralDirStruct.uncompressedSize.toString()
                return .folder(path: folderPath, size: folderSize)
            } else if entryType == .file {
                let filePath = self.extractPath(centralDirectoryStructure: centralDirStruct)
                let fileSize = centralDirStruct.uncompressedSize.toString()
                return .file(path: filePath, size: fileSize)
            } else {
                return CompressedFileType.none
            }
        }
    }
}
