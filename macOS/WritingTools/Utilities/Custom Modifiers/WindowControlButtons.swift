//
//  WindowControlButtons.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 20.07.25.
//

import SwiftUI

/// Minimal replica of the macOS traffic-light buttons.
struct WindowControlButtons: View {
    private struct Light: View {
        let color: Color
        let action: () -> Void
        var body: some View {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .onTapGesture(perform: action)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Light(color: Color(red: 0.99, green: 0.39, blue: 0.39)) {   // 🔴 close
                NSApp.keyWindow?.performClose(nil)
            }
            Light(color: Color(red: 0.99, green: 0.79, blue: 0.39)) {   // 🟡 minimise
                NSApp.keyWindow?.miniaturize(nil)
            }
            Light(color: Color(red: 0.34, green: 0.86, blue: 0.46)) {   // 🟢 zoom
                NSApp.keyWindow?.zoom(nil)
            }
        }
        .padding(.leading, 8)
        .padding(.top,   6)
    }
}
