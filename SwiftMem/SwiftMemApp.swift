//
//  SwiftMemApp.swift
//  SwiftMem
//
//  Created by Sankritya Thakur on 12/7/25.
//

import SwiftUI

@main
struct SwiftMemApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("SwiftMem")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Memory Graph Library")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
