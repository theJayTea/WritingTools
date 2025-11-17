//
//  InfoRow.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}

#Preview("InfoRow") {
    VStack(alignment: .leading) {
        InfoRow(label: "Version", value: "1.0")
        InfoRow(label: "Build", value: "100")
    }
    .padding()
}
