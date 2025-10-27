//
//  Drive_SpeedApp.swift
//  Drive Speed
//
//  Created by George Babichev on 10/27/25.
//

import SwiftUI

@main
struct Drive_SpeedApp: App {
    @State private var showAbout = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()

                if showAbout {
                    AboutView(isPresented: $showAbout)
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Drive Speed") {
                    showAbout = true
                }
            }
        }
    }
}
