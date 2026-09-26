import SwiftUI

struct ExplorerExpandedSliceView: View {
  @Bindable var session: ExplorerSession
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        SliceCanvasView(session: session)
          .padding(16)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        ExplorerAdjustmentBar(session: session)
          .padding(20)
          .background(.regularMaterial)
      }
      .background(ExplorerPalette.background)
      .navigationTitle("Horizontal slice")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", systemImage: "checkmark") { dismiss() }
        }
      }
    }
    .tint(ExplorerPalette.mint)
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
  }
}
