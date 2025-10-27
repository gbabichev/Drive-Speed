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

struct TestResult {
    let fileSize: String
    let fileSizeBytes: Int
    let readSpeed: Double // MB/s
    let writeSpeed: Double // MB/s
}

struct SpeedTestResult {
    let test100MB: TestResult
    let test1GB: TestResult
    let test10GB: TestResult
}

@MainActor
class DiskSpeedTester: NSObject, ObservableObject {
    @Published var isTestingActive = false
    @Published var testProgress: String = ""
    @Published var testResult: SpeedTestResult?

    private let testFileBaseName = "DiskSpeedTest_\(UUID().uuidString).bin"

    // Test configurations: (label, size in bytes)
    private let testConfigs = [
        ("100 MB", 100 * 1024 * 1024),
        ("1 GB", 1024 * 1024 * 1024),
        ("10 GB", 10 * 1024 * 1024 * 1024)
    ]

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

        // Run tests on background thread to prevent UI blocking
        DispatchQueue.global(qos: .userInitiated).async {
            // Find a writable location on the drive
            guard let writablePath = self.findWritablePath(on: diskPath) else {
                DispatchQueue.main.async {
                    self.testProgress = "Error: No writable location found on this drive. Check permissions."
                    self.isTestingActive = false
                }
                return
            }

            var results: [TestResult] = []

            do {
                // Run all three tests
                for (index, (label, fileSize)) in self.testConfigs.enumerated() {
                    let testNumber = index + 1
                    DispatchQueue.main.async {
                        self.testProgress = "Test \(testNumber)/3: \(label)"
                    }

                    let testFileName = "DiskSpeedTest_\(UUID().uuidString).bin"
                    let testFilePath = (writablePath as NSString).appendingPathComponent(testFileName)

                    // Write test
                    DispatchQueue.main.async {
                        self.testProgress = "Test \(testNumber)/3: \(label) - Writing..."
                    }
                    let writeSpeed = try self.performWriteTestSync(filePath: testFilePath, fileSize: fileSize)

                    // Read test
                    DispatchQueue.main.async {
                        self.testProgress = "Test \(testNumber)/3: \(label) - Reading..."
                    }
                    let readSpeed = try self.performReadTestSync(filePath: testFilePath, fileSize: fileSize)

                    // Cleanup
                    try FileManager.default.removeItem(atPath: testFilePath)

                    let result = TestResult(
                        fileSize: label,
                        fileSizeBytes: fileSize,
                        readSpeed: readSpeed,
                        writeSpeed: writeSpeed
                    )
                    results.append(result)
                }

                // Update results on main thread
                DispatchQueue.main.async {
                    if results.count == 3 {
                        self.testResult = SpeedTestResult(
                            test100MB: results[0],
                            test1GB: results[1],
                            test10GB: results[2]
                        )
                    }
                    self.testProgress = "All tests complete!"
                    self.isTestingActive = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.testProgress = "Error: \(error.localizedDescription)"
                    self.isTestingActive = false
                }
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

    private func performWriteTestSync(filePath: String, fileSize: Int) throws -> Double {
        let chunkSize = 8 * 1024 * 1024 // 8 MB chunks for better throughput measurement
        let chunk = Data(repeating: 0xAB, count: chunkSize)
        let numChunks = fileSize / chunkSize

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
        let speedMBps = Double(fileSize) / (1024 * 1024) / elapsed

        return speedMBps
    }

    private func performReadTestSync(filePath: String, fileSize: Int) throws -> Double {
        // Read the test file once for faster testing (especially for large files)
        let chunkSize = 8 * 1024 * 1024 // 8 MB chunks

        let startTime = Date()

        guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
            throw NSError(domain: "ReadTest", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to open file for reading"])
        }

        defer {
            fileHandle.closeFile()
        }

        // Read in chunks
        var bytesRead: UInt64 = 0
        while bytesRead < UInt64(fileSize) {
            let remainingBytes = fileSize - Int(bytesRead)
            let currentChunkSize = min(chunkSize, remainingBytes)

            let data = fileHandle.readData(ofLength: currentChunkSize)
            if data.isEmpty {
                break
            }
            bytesRead += UInt64(data.count)
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let speedMBps = Double(fileSize) / (1024 * 1024) / elapsed

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
