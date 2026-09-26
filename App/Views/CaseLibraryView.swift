import SwiftUI
import UniformTypeIdentifiers

/// Home: the sample case and the patient's imported reports.
struct CaseLibraryView: View {
  @Environment(CaseLibrary.self) private var library
  @State private var path: [ScanCase] = []
  @State private var isPickingFile = false
  @State private var isShowingSettings = false

  var body: some View {
    @Bindable var library = library
    NavigationStack(path: $path) {
      List {
        Section {
          VStack(alignment: .leading, spacing: 8) {
            Text("See inside your scan")
              .font(.title2.bold())
            Text("Import a radiology report and every finding is explained in plain words and pinned on a body you can peel apart. Fold the phone to cut through it.")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 4)
        }

        Section {
          Button {
            isPickingFile = true
          } label: {
            Label("Import a Report", systemImage: "document.badge.plus")
          }
          Button {
            Task {
              if let scanCase = await library.importSampleReport() { path.append(scanCase) }
            }
          } label: {
            Label("Try a Sample Report", systemImage: "text.page.badge.magnifyingglass")
          }
          if library.isImporting {
            HStack(spacing: 12) {
              ProgressView()
              Text(library.hasAPIKey ? "Claude is reading your report…" : "Reading your report…")
                .foregroundStyle(.secondary)
            }
          }
          if let message = library.importMessage {
            Label(message, systemImage: "info.circle")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        } footer: {
          Text(library.hasAPIKey ? "Reports are explained by Claude \(library.model.displayName)." : "Reports are read on this device. Add a Claude key in Settings for fuller explanations.")
        }

        Section("Sample") {
          NavigationLink(value: SampleCases.patientCT) {
            CaseRow(scanCase: SampleCases.patientCT)
          }
        }

        if !library.importedCases.isEmpty {
          Section("Your Reports") {
            ForEach(library.importedCases) { scanCase in
              NavigationLink(value: scanCase) {
                CaseRow(scanCase: scanCase)
              }
            }
            .onDelete { library.delete($0) }
          }
        }

        Section {
          Label("Generalizable explains; it doesn't diagnose. Findings are shown on a model body, not your own images. Always talk with your doctor.", systemImage: "stethoscope")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Generalizable")
      .navigationDestination(for: ScanCase.self) { scanCase in
        ViewerView(scanCase: scanCase)
      }
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("Import Report", systemImage: "plus") {
            isPickingFile = true
          }
        }
        ToolbarItem(placement: .secondaryAction) {
          Button("Settings", systemImage: "gearshape") {
            isShowingSettings = true
          }
        }
      }
      .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.pdf, .image, .plainText, .text]) { result in
        guard case .success(let url) = result else { return }
        Task {
          if let scanCase = await library.importFile(at: url) { path.append(scanCase) }
        }
      }
      .sheet(isPresented: $isShowingSettings) {
        SettingsView()
      }
    }
  }
}

private struct CaseRow: View {
  var scanCase: ScanCase

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: scanCase.kind == .sample ? "figure.stand" : "text.document")
        .font(.title2)
        .foregroundStyle(.tint)
        .frame(width: 36)
      VStack(alignment: .leading, spacing: 2) {
        Text(scanCase.title)
          .font(.headline)
        Text("\(scanCase.findings.count) finding\(scanCase.findings.count == 1 ? "" : "s") · \(scanCase.subtitle)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }
}
