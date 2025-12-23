//
//  PermissionRow.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI

struct PermissionRow: View {
  enum Status {
    case granted
    case missing
  }

  let icon: String
  let title: String
  let status: Status
  let explanation: String
  let primaryActionTitle: String
  let secondaryActionTitle: String
  let onPrimary: () -> Void
  let onSecondary: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: icon)
        .font(.system(size: 28))
        .foregroundStyle(status == .granted ? .green : .blue)
        .frame(width: 36)

      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(title).font(.headline)
          Spacer()
          statusBadge
        }

        Text(explanation)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        HStack {
          Button(primaryActionTitle, action: onPrimary)
            .buttonStyle(.borderedProminent)
            .disabled(status == .granted)

          Button(secondaryActionTitle, action: onSecondary)
            .buttonStyle(.bordered)

          Spacer()
        }
        .padding(.top, 4)
      }
    }
    .padding(12)
    .background(Color(.controlBackgroundColor))
    .clipShape(.rect(cornerRadius: 10))
  }

  @ViewBuilder
  private var statusBadge: some View {
    HStack(spacing: 6) {
      Image(
        systemName: status == .granted
          ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
      )
      .foregroundStyle(status == .granted ? .green : .orange)
      Text(status == .granted ? "Granted" : "Required")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}
