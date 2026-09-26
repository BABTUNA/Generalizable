// DemoBanner.swift
// Permanent banner shown on every screen (A6 ruling).

import SwiftUI

struct DemoBanner: View {
    var body: some View {
        Text("Demo only — public open-source research data. Not a diagnosis.")
            .font(.footnote)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Color.yellow.opacity(0.25))
            .accessibilityElement(children: .combine)
    }
}
