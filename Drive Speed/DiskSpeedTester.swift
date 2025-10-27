//
//  DiskSpeedTester.swift
//  Drive Speed
//
//  Created by George Babichev on 10/27/25.
//

import Foundation
import Combine

struct DiskInfo: Hashable, Equatable {
    let name: String
    let path: String
    let available: Int64
}

struct SpeedTestResult {
    let readSpeed: Double // MB/s
    let writeSpeed: Double // MB/s
}

@MainActor
class DiskSpeedTester: NSObject, ObservableObject {
    @Published var isTestingActive = false
    @Published var testProgress: String = ""
    @Published var testResult: SpeedTestResult?

    private let testFileSize: Int = 100 * 1024 * 1024 // 100 MB
    private let testFileName = "DiskSpeedTest_\(UUID().uuidString).bin"

    // Get list of available drives
    func getAvailableDrives() -> [DiskInfo] {
        let fileManager = FileManager.default
        var drives: [DiskInfo] = []

        do {
            let mountedVolumes = try fileManager.contentsOfDirectory(atPath: "/Volumes")

            for volume in mountedVolumes {
                let volumePath = "/Volumes/\(volume)"

                // Skip system volumes
                if volumePath.contains("System") || volumePath.contains(".") {
                    continue
                }

                // Get available space
                if let attributes = try? fileManager.attributesOfFileSystem(forPath: volumePath) {
                    if let availableSpace = attributes[.systemFreeSize] as? Int64 {
                        let diskInfo = DiskInfo(
                            name: volume,
                            path: volumePath,
                            available: availableSpace
                        )
                        drives.append(diskInfo)
                    }
                }
            }
        } catch {
            print("Error getting mounted volumes: \(error)")
        }

        return drives
    }

    // Run speed test on a selected drive
    func runSpeedTest(on diskPath: String) async {
        DispatchQueue.main.async {
            self.isTestingActive = true
            self.testProgress = "Finding writable location..."
            self.testResult = nil
        }

        // Find a writable location on the drive
        guard let writablePath = findWritablePath(on: diskPath) else {
            DispatchQueue.main.async {
                self.testProgress = "Error: No writable location found on this drive. Check permissions."
                self.isTestingActive = false
            }
            return
        }

        let testFilePath = (writablePath as NSString).appendingPathComponent(testFileName)
        var readSpeed: Double = 0
        var writeSpeed: Double = 0

        do {
            // Write test
            DispatchQueue.main.async {
                self.testProgress = "Testing write speed..."
            }
            writeSpeed = try await performWriteTest(filePath: testFilePath)

            // Read test
            DispatchQueue.main.async {
                self.testProgress = "Testing read speed..."
            }
            readSpeed = try await performReadTest(filePath: testFilePath)

            // Cleanup
            DispatchQueue.main.async {
                self.testProgress = "Cleaning up..."
            }
            try FileManager.default.removeItem(atPath: testFilePath)

            // Update results
            DispatchQueue.main.async {
                self.testResult = SpeedTestResult(readSpeed: readSpeed, writeSpeed: writeSpeed)
                self.testProgress = "Test complete!"
                self.isTestingActive = false
            }
        } catch {
            DispatchQueue.main.async {
                self.testProgress = "Error: \(error.localizedDescription)"
                self.isTestingActive = false
            }
        }
    }

    // Find a writable location on the target drive
    private func findWritablePath(on diskPath: String) -> String? {
        let fileManager = FileManager.default
        let testFileName = "WriteTest_\(UUID().uuidString)"

        // Try locations in order of preference
        let locationsToTry = [
            diskPath, // Root of drive
            (diskPath as NSString).appendingPathComponent("Users"),
            (diskPath as NSString).appendingPathComponent("Volumes"),
            (diskPath as NSString).appendingPathComponent("tmp"),
            NSTemporaryDirectory(), // System temp directory as fallback
        ]

        for location in locationsToTry {
            // Check if directory exists
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: location, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            // Try to create a test file to verify write permissions
            let testPath = (location as NSString).appendingPathComponent(testFileName)
            do {
                let testData = Data([0x00])
                try testData.write(to: URL(fileURLWithPath: testPath), options: .atomic)

                // Clean up test file
                try? fileManager.removeItem(atPath: testPath)

                // This location is writable
                return location
            } catch {
                // This location is not writable, try next
                continue
            }
        }

        return nil
    }

    private func performWriteTest(filePath: String) async throws -> Double {
        let chunkSize = 4 * 1024 * 1024 // 4 MB chunks for better throughput measurement
        let chunk = Data(repeating: 0xAB, count: chunkSize)
        let numChunks = testFileSize / chunkSize

        let startTime = Date()

        // Create file and write in chunks
        FileManager.default.createFile(atPath: filePath, contents: nil, attributes: nil)

        guard let fileHandle = FileHandle(forWritingAtPath: filePath) else {
            throw NSError(domain: "WriteTest", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to open file for writing"])
        }

        defer {
            fileHandle.closeFile()
        }

        // Write chunks
        for _ in 0..<numChunks {
            try fileHandle.write(contentsOf: chunk)
        }

        // Sync to disk
        fileHandle.synchronizeFile()

        let elapsed = Date().timeIntervalSince(startTime)
        let speedMBps = Double(testFileSize) / (1024 * 1024) / elapsed

        return speedMBps
    }

    private func performReadTest(filePath: String) async throws -> Double {
        // Read the test file multiple times for better accuracy
        let iterations = 3
        var totalTime: TimeInterval = 0
        let chunkSize = 4 * 1024 * 1024 // 4 MB chunks

        for _ in 0..<iterations {
            let startTime = Date()

            guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
                throw NSError(domain: "ReadTest", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to open file for reading"])
            }

            defer {
                fileHandle.closeFile()
            }

            // Read in chunks
            var bytesRead: UInt64 = 0
            while bytesRead < UInt64(testFileSize) {
                let remainingBytes = testFileSize - Int(bytesRead)
                let currentChunkSize = min(chunkSize, remainingBytes)

                let data = fileHandle.readData(ofLength: currentChunkSize)
                if data.isEmpty {
                    break
                }
                bytesRead += UInt64(data.count)
            }

            let elapsed = Date().timeIntervalSince(startTime)
            totalTime += elapsed

            // Clear filesystem cache between reads
            await clearFileSystemCache()
        }

        let averageTime = totalTime / Double(iterations)
        let speedMBps = Double(testFileSize) / (1024 * 1024) / averageTime

        return speedMBps
    }

    private func clearFileSystemCache() async {
        // Use purge command to clear filesystem cache
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/purge")

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("Could not purge cache: \(error)")
        }
    }
}
