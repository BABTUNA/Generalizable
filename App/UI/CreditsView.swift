// CreditsView.swift
// Lists each bundled case's meta.json source/license (A6 ruling).

import SwiftUI

struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss
    let credits: [CaseCredit]

    var body: some View {
        NavigationStack {
            List(credits) { credit in
                Section(credit.displayName) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Source").font(.caption).foregroundStyle(.secondary)
                        Text(credit.source)
                    }
                    .padding(.vertical, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("License").font(.caption).foregroundStyle(.secondary)
                        Text(credit.license)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Credits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
