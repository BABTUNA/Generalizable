import SwiftUI

/// The case viewer. On iPhone Duo's inner display an ArrangementView keeps the scan and the controls on
/// opposite sides of the fold, so in the table pose the live cut stands up on the top half while the
/// explanation and controls lie flat on the bottom half. Elsewhere a split layout does the same job.
struct ViewerView: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var model: ViewerModel

  init(scanCase: ScanCase) {
    _model = State(initialValue: ViewerModel(scanCase: scanCase))
  }

  var body: some View {
    arrangement
      .modifier(HingeReader(model: model))
      .navigationTitle(model.scanCase.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Toggle(isOn: Binding(get: { model.mode == .ct }, set: { model.mode = $0 ? .ct : .layers })) {
            Label("CT Scan", systemImage: "circle.lefthalf.filled")
          }
        }
        ToolbarItem(placement: .secondaryAction) {
          Button("Reset View", systemImage: "arrow.counterclockwise") {
            model.reset()
          }
        }
      }
  }

  @ViewBuilder
  private var arrangement: some View {
    if #available(iOS 27.1, *), horizontalSizeClass == .regular {
      ArrangementView {
        ScanStageView(model: model)
      } secondary: {
        ControlPanelView(model: model)
      }
      .arrangementViewStyle(.split)
      .background(Color(.systemGroupedBackground))
    } else {
      GeometryReader { proxy in
        if proxy.size.width > proxy.size.height * 1.1 {
          HStack(spacing: 0) {
            ScanStageView(model: model)
            ControlPanelView(model: model)
              .frame(width: min(420, proxy.size.width * 0.45))
          }
        } else {
          VStack(spacing: 0) {
            ScanStageView(model: model)
              .frame(height: proxy.size.height * 0.52)
            ControlPanelView(model: model)
          }
        }
      }
      .background(Color(.systemGroupedBackground))
    }
  }
}
