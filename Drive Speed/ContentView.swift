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
            // Title
            Text("Drive Speed Tester")
                .font(.title)
                .fontWeight(.bold)

            // Drive Selection
            VStack(alignment: .leading, spacing: 10) {
                Text("Select Drive")
                    .font(.headline)

                Picker("Drive", selection: $selectedDrive) {
                    Text("Choose a drive...").tag(Optional<DiskInfo>(nil))

                    ForEach(availableDrives, id: \.path) { drive in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(drive.name)
                        }
                        .tag(Optional(drive))
                    }
                }
                .pickerStyle(.segmented)

                // Drive info
                if let selectedDrive = selectedDrive {
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

            Divider()

            // Test Controls
            VStack(spacing: 15) {
                Button(action: startTest) {
                    if tester.isTestingActive {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Testing...")
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                            Text("Start Speed Test")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedDrive == nil || tester.isTestingActive)

                // Progress text
                if !tester.testProgress.isEmpty {
                    Text(tester.testProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Results
            if let result = tester.testResult {
                VStack(spacing: 15) {
                    Text("Speed Test Results")
                        .font(.headline)

                    HStack(spacing: 30) {
                        VStack(alignment: .center, spacing: 8) {
                            Text("Read Speed")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(String(format: "%.2f MB/s", result.readSpeed))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                        .frame(maxWidth: .infinity)

                        VStack(alignment: .center, spacing: 8) {
                            Text("Write Speed")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(String(format: "%.2f MB/s", result.writeSpeed))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
            } else if !tester.testProgress.isEmpty {
                VStack {
                    ProgressView()
                    Text("Testing in progress...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
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
}
