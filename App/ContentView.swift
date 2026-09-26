import SwiftUI

struct ContentView: View {
  @State private var path = NavigationPath()
  @State private var showingCredits: Bool

  init() {
    // `-credits` is a screenshot-verification convenience (not part of the scripted-screenshot
    // launch-argument spec), so a build_sim.sh run can capture the credits sheet directly.
    _showingCredits = State(initialValue: CommandLine.arguments.contains("-credits"))
  }

  private let launchArgs = LaunchArguments.parsed
  private let summaries = CaseCatalog.availableSummaries()

  var body: some View {
    VStack(spacing: 0) {
      DemoBanner()

      NavigationStack(path: $path) {
        List(summaries) { summary in
          NavigationLink(value: summary.id) {
            VStack(alignment: .leading, spacing: 4) {
              Text(summary.displayName).font(.headline)
              Text("\(summary.layerCount) layer\(summary.layerCount == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
          }
          .accessibilityLabel("\(summary.displayName), \(summary.layerCount) layers")
        }
        .navigationTitle("Generalizable")
        .navigationDestination(for: String.self) { caseName in
          ViewerContainerView(caseName: caseName, launchArgs: launchArgs)
        }
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Credits") { showingCredits = true }
          }
        }
      }
    }
    .sheet(isPresented: $showingCredits) {
      CreditsView(credits: CaseCatalog.credits())
    }
    .onAppear {
      if let requested = launchArgs.caseName,
         summaries.contains(where: { $0.id == requested }),
         path.isEmpty {
        path.append(requested)
      }
    }
  }
}
