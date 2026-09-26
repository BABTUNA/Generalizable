import SwiftUI

struct FoldScanInspector: View {
  @Bindable var session: FoldScanSession
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("CT window") {
          Picker("Show", selection: $session.window) {
            ForEach(ScanWindow.allCases) { window in Text(window.rawValue).tag(window) }
          }
          .pickerStyle(.segmented)
          LabeledContent("Width", value: "\(Int(session.window.width)) HU")
          LabeledContent("Level", value: "\(Int(session.window.level)) HU")
        }
        Section {
          Toggle("Follow the fold", isOn: Binding(get: { session.followsFold }, set: session.setFollowsFold))
          if let angle = session.hingeAngle { LabeledContent("Hinge angle", value: "\(Int(angle.rounded()))°") }
          Button("Center slice", systemImage: "viewfinder") { session.scrub(0.5) }
        } header: { Text("Fold control") } footer: {
          Text("180° selects the first layer. Folding toward 90° travels to the last. Touching the slider pauses fold control; turn Follow fold on to reconnect.")
        }
        Section("Scan") {
          if let volume = session.volume {
            LabeledContent("Dimensions", value: volume.dimensions.map(String.init).joined(separator: " × "))
          }
          Button("Open demo CT", systemImage: "arrow.counterclockwise") {
            Task { await session.loadDemo(); dismiss() }
          }
        }
      }
      .navigationTitle("View controls").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } } }
    }
    .tint(ScanStyle.accent)
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }
}
