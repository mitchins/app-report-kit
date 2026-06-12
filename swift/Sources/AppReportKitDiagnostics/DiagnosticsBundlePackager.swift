import Foundation

public protocol DiagnosticsBundlePackager {
    func package(at directoryURL: URL, filename: String) throws -> URL
}

public struct ZipDiagnosticsBundlePackager: DiagnosticsBundlePackager {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func package(at directoryURL: URL, filename: String) throws -> URL {
        let archiveURL = directoryURL.appendingPathComponent(filename)
        let files = collectFiles(in: directoryURL, excluding: archiveURL)
        let archiveData = try makeArchiveData(for: files)
        try archiveData.write(to: archiveURL, options: .atomic)
        return archiveURL
    }

    private func collectFiles(in rootURL: URL, excluding excludedFileURL: URL) -> [PackagedFile] {
        let standardizedRootURL = rootURL.standardizedFileURL
        let standardizedExcludedFileURL = excludedFileURL.standardizedFileURL
        guard let enumerator = fileManager.enumerator(
            at: standardizedRootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [PackagedFile] = []
        let rootComponents = standardizedRootURL.pathComponents
        for case let fileURL as URL in enumerator {
            let standardizedFileURL = fileURL.standardizedFileURL
            guard
                let resourceValues = try? standardizedFileURL.resourceValues(forKeys: [.isRegularFileKey]),
                standardizedFileURL != standardizedExcludedFileURL,
                resourceValues.isRegularFile == true
            else {
                continue
            }

            let relativeComponents = Array(standardizedFileURL.pathComponents.dropFirst(rootComponents.count))
            let relativePath = relativeComponents.isEmpty
                ? standardizedFileURL.lastPathComponent
                : NSString.path(withComponents: relativeComponents)
            files.append(.init(fileURL: standardizedFileURL, relativePath: relativePath))
        }

        return files
    }

    private func makeArchiveData(for files: [PackagedFile]) throws -> Data {
        var localEntries: [ZipArchiveEntry] = []
        var centralDirectory = Data()
        var localData = Data()

        for file in files {
            let relativePath = file.relativePath
            let fileData = try Data(contentsOf: file.fileURL)
            let crc = UInt32(crc32(fileData))
            let fileNameData = relativePath.data(using: .utf8) ?? Data()

            let localHeaderOffset = UInt32(localData.count)
            localEntries.append(.init(
                name: relativePath,
                crc: crc,
                compressedSize: UInt32(fileData.count),
                uncompressedSize: UInt32(fileData.count),
                localHeaderOffset: localHeaderOffset
            ))

            var header = Data()
            header.appendUInt32(0x0403_4b50)
            header.appendUInt16(20)
            header.appendUInt16(0)
            header.appendUInt16(0)
            header.appendUInt16(0)
            header.appendUInt16(0)
            header.appendUInt32(crc)
            header.appendUInt32(UInt32(fileData.count))
            header.appendUInt32(UInt32(fileData.count))
            header.appendUInt16(UInt16(fileNameData.count))
            header.appendUInt16(0)
            header.append(fileNameData)
            header.append(fileData)

            localData.append(header)
        }

        let centralDirectoryOffset = UInt32(localData.count)
        for entry in localEntries {
            let fileNameData = entry.name.data(using: .utf8) ?? Data()
            var header = Data()
            header.appendUInt32(0x0201_4b50)
            header.appendUInt16(20)
            header.appendUInt16(20)
            header.appendUInt16(0)
            header.appendUInt16(0)
            header.appendUInt16(0)
            header.appendUInt16(0)
            header.appendUInt32(entry.crc)
            header.appendUInt32(entry.compressedSize)
            header.appendUInt32(entry.uncompressedSize)
            header.appendUInt16(UInt16(fileNameData.count))
            header.appendUInt16(0)
            header.appendUInt16(0)
            header.appendUInt16(0)
            header.appendUInt16(0)
            header.appendUInt32(0)
            header.appendUInt32(entry.localHeaderOffset)
            header.append(fileNameData)
            centralDirectory.append(header)
        }

        var archive = localData
        archive.append(centralDirectory)

        var trailer = Data()
        trailer.appendUInt32(0x0605_4b50)
        trailer.appendUInt16(0)
        trailer.appendUInt16(0)
        trailer.appendUInt16(UInt16(localEntries.count))
        trailer.appendUInt16(UInt16(localEntries.count))
        trailer.appendUInt32(UInt32(centralDirectory.count))
        trailer.appendUInt32(centralDirectoryOffset)
        trailer.appendUInt16(0)
        archive.append(trailer)

        return archive
    }

    private func crc32(_ data: Data) -> UInt64 {
        let table = (0..<256).map { i -> UInt64 in
            var crc = UInt64(i)
            for _ in 0..<8 {
                if (crc & 1) == 1 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
            return crc
        }

        var crc: UInt64 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt64(byte)) & 0xFF)
            crc = (crc >> 8) ^ table[index]
        }

        return crc ^ 0xFFFF_FFFF
    }
}

private struct ZipArchiveEntry {
    let name: String
    let crc: UInt32
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let localHeaderOffset: UInt32
}

private struct PackagedFile {
    let fileURL: URL
    let relativePath: String
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8((value >> 0) & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8((value >> 0) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
