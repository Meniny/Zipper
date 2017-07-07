<p align="center">
  <img alt="Version" src="https://img.shields.io/badge/version-1.0.0-brightgreen.svg">
  <img alt="Author" src="https://img.shields.io/badge/author-Meniny-blue.svg">
  <img alt="Build Passing" src="https://img.shields.io/badge/build-passing-brightgreen.svg">
  <img alt="Swift" src="https://img.shields.io/badge/swift-3.0%2B-orange.svg">
  <br/>
  <img alt="Platforms" src="https://img.shields.io/badge/platform-macOS%20%7C%20iOS%20%7C%20watchOS%20%7C%20tvOS-lightgrey.svg">
  <img alt="MIT" src="https://img.shields.io/badge/license-MIT-blue.svg">
  <br/>
  <img alt="Cocoapods" src="https://img.shields.io/badge/cocoapods-compatible-brightgreen.svg">
</p>

`Zipper` is a library to create, read and modify ZIP archive files, written in Swift.

## Requirements

- iOS 9.0+
- macOS 10.11+
- tvOS 9.0+
- watchOS 2.0+
- Linux (with `zlib`)
- Xcode 8.0+
- Swift 3.0+

## Installation

#### CocoaPods

```ruby
source 'https://github.com/CocoaPods/Specs.git'
platform :ios, '9.0'
use_frameworks!
target 'YOUR_TARGET_NAME' do
    pod 'Zipper'
end
```

## Contribution

You are welcome to fork and submit pull requests.

## License

Zipper is released under the MIT License.

## Usage

```swift
let fileManager = FileManager()
let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
```

#### Zipping

```swift
var archiveURL = currentDirectoryURL.appendPathComponent("archive.zip")
var resourcesURL = currentDirectoryURL.appendPathComponent("directory")
// zip:
do {
  try fileManager.zip(item: resourcesURL, to: archive)
} catch _ {}
// or:
guard let archive = Zipper(url: archiveURL, accessMode: .create) else  { return }
do {
  try archive.zip(item: resourcesURL)
} catch _ {}
```

#### Unzipping

```swift
var archiveURL = currentDirectoryURL.appendPathComponent("archive.zip")
var destinationURL = currentDirectoryURL.appendPathComponent("directory")
// unzip:
do {
  try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
  try fileManager.unzip(item: archiveURL, to: destinationURL)
} catch _ {}
// or:
guard let archive = Zipper(url: archiveURL, accessMode: .read) else  { return }
do {
  try archive.unzip(to: destinationURL)
} catch _ {}
```

#### Accessing individual Entries

```swift
var archiveURL = currentDirectoryURL.appendPathComponent("archive.zip")
guard let archive = Zipper(url: archiveURL, accessMode: .read) else  { return }
guard let entry = archive["file.txt"] else { return }
var destinationURL = currentDirectoryURL.appendPathComponent("output.txt")

do {
    try archive.extract(entry, to: destinationURL)
} catch {}
```

#### Adding/Removing Entries

```swift
var archiveURL = currentDirectoryURL.appendPathComponent("archive.zip")
var fileURL = currentDirectoryURL.appendPathComponent("file.ext")
```

Adding:

``` swift
guard let archive = Zipper(url: archiveURL, accessMode: .update) else { return }
do {
    try archive.addEntry(with: fileURL.lastPathComponent, relativeTo: fileURL.deletingLastPathComponent())
} catch {}
```

Removing:

```swift
guard let entry = archive["file.txt"] else { return }
do {
    try archive.remove(entry)
} catch {}
```
