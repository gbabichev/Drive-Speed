//
//  ContentView.swift
//  Drive Speed
//
//  Created by George Babichev on 10/27/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var tester = DiskSpeedTester()
    @State private var selectedDrive: DiskInfo?
    @State private var availableDrives: [DiskInfo] = []

    var body: some View {
        VStack(spacing: 20) {
            // Drive info
            if let selectedDrive = selectedDrive {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Drive Info")
                        .font(.headline)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Path: \(selectedDrive.path)")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            let availableGB = Double(selectedDrive.available) / (1024 * 1024 * 1024)
                            Text(String(format: "Available: %.2f GB", availableGB))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            }

            // Progress text
            if !tester.testProgress.isEmpty {
                Text(tester.testProgress)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            // Results in ScrollView
            ScrollView {
                if let results = tester.testResult {
                    VStack(spacing: 12) {
                        Text("Speed Test Results")
                            .font(.headline)

                        // 100 MB Test
                        TestResultRow(test: results.test100MB)

                        // 1 GB Test
                        TestResultRow(test: results.test1GB)

                        // 10 GB Test
                        TestResultRow(test: results.test10GB)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                } else if !tester.testProgress.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Testing in progress...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        VStack(spacing: 8) {
                            Text("Ready to Test")
                                .font(.headline)

                            Text("Select a drive from the toolbar and click 'Start Speed Test' to begin")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Drive", selection: $selectedDrive) {
                    Text("Choose a drive...").tag(Optional<DiskInfo>(nil))
                    
                    ForEach(availableDrives, id: \.path) { drive in
                        Text(drive.name).tag(Optional(drive))
                    }
                }
            }
            ToolbarItem(placement: .navigation) {
                Button(action: refreshDrives) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Rescan available drives")
            }
            
            ToolbarItem(placement: .status) {
                Spacer()
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button(action: startTest) {
                    Image(systemName: "bolt.fill")
                }
                .disabled(selectedDrive == nil || tester.isTestingActive)
            }
        }
        .onAppear {
            availableDrives = tester.getAvailableDrives()
        }
    }

    private func startTest() {
        guard let drive = selectedDrive else { return }

        Task {
            await tester.runSpeedTest(on: drive.path)
        }
    }

    private func refreshDrives() {
        availableDrives = tester.getAvailableDrives()
    }
}

struct TestResultRow: View {
    let test: TestResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(test.fileSize)
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(spacing: 20) {
                VStack(alignment: .center, spacing: 6) {
                    Text("Read")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(String(format: "%.2f", test.readSpeed))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)

                    Text("MB/s")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .center, spacing: 6) {
                    Text("Write")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(String(format: "%.2f", test.writeSpeed))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.green)

                    Text("MB/s")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}
