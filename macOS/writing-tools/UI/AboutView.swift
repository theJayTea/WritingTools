import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("About Writing Tools")
                .font(.largeTitle)
                .bold()
            
            Text("Writing Tools is a free & lightweight tool that helps you improve your writing with AI, similar to Apple's new Apple Intelligence feature.")
                .multilineTextAlignment(.center)
            
            VStack(spacing: 10) {
                Text("Created with care by Jesai, a high school student.")
                    .bold()
                
                Link("Email: jesaitarun@gmail.com",
                     destination: URL(string: "mailto:jesaitarun@gmail.com")!)
                
                Link("Check out Bliss AI on Google Play",
                     destination: URL(string: "https://play.google.com/store/apps/details?id=com.jesai.blissai")!)
            }
            
            Divider()
            
            Text("Version: 5.0 (Codename: Impressively Improved)")
                .font(.caption)
            
            Button("Check for Updates") {
                NSWorkspace.shared.open(URL(string: "https://github.com/theJayTea/WritingTools/releases")!)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 400, height: 400)
    }
}