import SwiftUI

struct AppleIntelligenceSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("On-device model")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let reason = AppleIntelligenceProvider.unavailabilityReason {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else {
                Label("Apple Intelligence is ready. No API key needed; text never leaves your Mac.",
                      systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }

            Text("Images are converted to text with Apple Vision before being sent to the model.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
