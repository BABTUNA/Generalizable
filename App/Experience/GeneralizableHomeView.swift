import SwiftUI

struct GeneralizableHomeView: View {
  var body: some View {
    ImmersiveExplorerView()
    .tint(ExplorerPalette.mint)
    .preferredColorScheme(.dark)
  }
}
