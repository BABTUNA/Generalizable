// ViewerContainerView.swift
// Loads a CaseBundle off the main thread with a spinner and a readable error, then hands off to
// ViewerView once loaded.

import SwiftUI

struct ViewerContainerView: View {
    let caseName: String
    var launchArgs: LaunchArguments = .parsed

    @State private var model: ViewerModel?
    @State private var loadErrorDescription: String?

    var body: some View {
        Group {
            if let model {
                ViewerView(model: model)
            } else if let loadErrorDescription {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                    Text("Couldn't load \(CaseCatalog.displayName(for: caseName))")
                        .font(.headline)
                    Text(loadErrorDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal)
                }
                .padding()
                .accessibilityElement(children: .combine)
            } else {
                ProgressView("Loading \(CaseCatalog.displayName(for: caseName))…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(CaseCatalog.displayName(for: caseName))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: caseName) {
            await load()
        }
    }

    private func load() async {
        model = nil
        loadErrorDescription = nil
        let name = caseName
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try CaseBundle.bundled(name)
            }.value
            model = ViewerModel(bundle: loaded, launchArgs: launchArgs)
        } catch {
            loadErrorDescription = "\(error)"
        }
    }
}
