import SwiftUI

@main
struct AppDefinition: App {
  @State private var library = CaseLibrary()

  var body: some Scene {
    WindowGroup {
      CaseLibraryView()
        .environment(library)
    }
  }
}
