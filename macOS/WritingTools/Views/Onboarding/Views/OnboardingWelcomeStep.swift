//
//  OnboardingWelcomeStep.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI

struct OnboardingWelcomeStep: View {
  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "sparkles")
        .resizable()
        .scaledToFit()
        .frame(width: 60, height: 60)
        .foregroundColor(.accentColor)
        .padding(.bottom, 4)

      VStack(alignment: .leading, spacing: 10) {
        Label(
          "Improve your writing with one shortcut",
          systemImage: "square.and.pencil"
        )
        Label(
          "Works in any app that supports copy & paste",
          systemImage: "app.badge"
        )
        Label(
          "Preserves formatting for supported apps",
          systemImage: "note.text"
        )
        Label(
          "Custom commands & per-command shortcuts",
          systemImage: "command.square.fill"
        )
      }
      .font(.title3)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 12)

      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Text("How it works")
            .font(.headline)
          Text(
            """
            WritingTools briefly copies your selection, sends it to your \
            chosen AI provider (or a local model), and then pastes the \
            result back—preserving formatting when supported.
            """
          )
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
      }

      Text("You can change any setting later in Settings.")
        .font(.footnote)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
