import SwiftUI

struct GeneralizableHomeView: View {
  var body: some View {
    TabView {
      Tab("Explore", systemImage: "cube.transparent") {
        ImmersiveExplorerView()
      }
      Tab("Case library", systemImage: "text.document") {
        CaseLibraryView()
      }
    }
    .tint(ExplorerPalette.mint)
    .preferredColorScheme(.dark)
  }
}
