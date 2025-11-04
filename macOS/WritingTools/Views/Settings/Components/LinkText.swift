//
//  LinkText.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI
import AppKit

struct LinkText: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("Local LLMs: use the instructions on")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("GitHub Page.")
                .font(.caption)
                .foregroundColor(.blue)
                .underline()
                .onTapGesture {
                    if let url = URL(string: "https://github.com/theJayTea/WritingTools?tab=readme-ov-file#-optional-ollama-local-llm-instructions") {
                        NSWorkspace.shared.open(url)
                    }
                }
        }
    }
}
