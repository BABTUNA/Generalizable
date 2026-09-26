import SwiftUI

// L3c-render test wiring, this branch only (docs/contracts/render-interface.md).
// The Commander drops this change at merge and keeps L3b's ContentView.
struct ContentView: View {
  var body: some View {
    RenderTestView()
  }
}