import SwiftUI

struct FoldScanAboutView: View {
  var isDemo: Bool
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section("Fold through anatomy") {
          Text("A native CT cross-section viewer inspired by BodyMaps. The hinge acts as a physical control for moving through the scan. The locator line shows exactly where the current layer sits.")
          Link("BodyMaps project", destination: URL(string: "https://github.com/BodyMaps/BodyMaps-website")!)
        }
        Section("Scan data") {
          Text(isDemo ? "The bundled torso CT is a real demonstration volume from NiiVue. It contains 89 axial layers at 5 mm spacing. It is not a scan of you." : "This scan was opened locally. Processing stays on your device; no scan data is uploaded.")
          Text("Use the folder button to open a NIfTI-1 CT scan (.nii or .nii.gz). This version supports axis-aligned, single-volume scans up to 40 million voxels.")
          Text("For exploration and education, not clinical interpretation.").foregroundStyle(.secondary)
          Link("NiiVue demo data", destination: URL(string: "https://github.com/niivue/niivue/tree/main/packages/niivue/demos/images")!)
        }
        Section("NiiVue attribution") {
          Text((try? String(contentsOf: Bundle.main.url(forResource: "NiiVue-LICENSE", withExtension: "txt")!, encoding: .utf8)) ?? "Copyright (c) 2021, Niivue. BSD 2-Clause License.")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
      .navigationTitle("About").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } } }
    }
    .presentationDetents([.large])
  }
}
