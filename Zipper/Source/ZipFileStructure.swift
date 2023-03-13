//
//  ZipFileManager.swift
//  Zip preview
//
//  Created by DucTran on 10/03/2023.
//

import Foundation

enum StructureKey: String {
    case file
    case folder
}

protocol CompletedStructure {
    var path: String { get set }
    var name: String { get }
    var size: String { get set }
}

class CompletedFileStructure: CompletedStructure {
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

class CompletedFolderStructure: CompletedStructure {
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

class CompressFileManager {
    
    func compressFile(on inputPath: URL, to outputPath: URL? = nil) throws -> URL {
        let fileManager = FileManager()
        if fileManager.fileExists(atPath: inputPath.path) {
            if let outputPath = outputPath {
                do {
                    try fileManager.zip(item: inputPath, to: outputPath)
                } catch {
                    throw CompressFileError.cannotZipFile
                }
                return outputPath
            } else {
                let directoryPath = inputPath.deletingLastPathComponent()
                do {
                    try fileManager.zip(item: inputPath, to: directoryPath)
                } catch {
                    throw CompressFileError.cannotZipFile
                }
                return directoryPath
            }
        } else {
            throw CompressFileError.noSuchZipFile
        }
    }
    
    func decompressFile(on inputPath: URL, to outputPath: URL? = nil) throws -> URL {
        let fileManager = FileManager()
        if fileManager.fileExists(atPath: inputPath.path) {
            if let outputPath = outputPath {
                return outputPath
            } else {
                let directoryPath = inputPath.deletingLastPathComponent()
                do {
                    try fileManager.createDirectory(at: directoryPath, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    throw CompressFileError.createFileDecompressError
                }
                do {
                    try fileManager.unzip(item: inputPath, to: directoryPath)
                } catch {
                    throw CompressFileError.cannotUnzipFile
                }
                return directoryPath
            }
        } else {
            throw CompressFileError.noSuchZipFile
        }
    }
    
    func decompressIndividualFile(in zipFilePath: URL,
                                  with fileName: String,
                                  output container: URL,
                                  completion: @escaping (Result<URL,Error>) -> Void) {
        guard let archive = Zipper(url: zipFilePath, accessMode: .read) else  {
            completion(.failure(CompressFileError.noSuchZipFile))
            return
        }
        guard let entry = archive[fileName] else {
            completion(.failure(CompressFileError.noSuchFileInZip))
            return
        }
        do {
            if #available(iOS 16.0, *) {
                _ = try archive.extract(entry, to: container.appending(path: fileName))
                completion(.success(container.appending(path: fileName)))
            } else {
                // Fallback on earlier versions
                _ = try archive.extract(entry, to: container.appendingPathComponent(fileName))
                completion(.success(container.appendingPathComponent(fileName)))
            }
        } catch {
            completion(.failure(CompressFileError.cannotUnzipFile))
        }
    }
    
    
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
    
    
    func previewStructure(on url: URL) -> [CompletedFolderStructure]? {
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

