import SwiftUI
import simd

/// The live cross-section with finding markers, the side map that shows where the cut is, and the angle readout.
struct ScanStageView: View {
  var model: ViewerModel
  @State private var dragStartOffset: Double?
  @AccessibilityFocusState private var focused: Bool

  private var detent: Int { Int((model.tilt / 45).rounded()) }

  var body: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height)
      ZStack {
        Color.black

        if let image = model.sliceImage {
          Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.medium)
            .aspectRatio(1, contentMode: .fit)
            .frame(width: side, height: side)
            .overlay { markers(size: CGSize(width: side, height: side)) }
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAdjustableAction { direction in
              switch direction {
              case .increment: model.manualTilt = min(model.manualTilt + 15, 90)
              case .decrement: model.manualTilt = max(model.manualTilt - 15, 0)
              @unknown default: break
              }
            }
        } else {
          ProgressView().tint(.white)
        }

        VStack {
          HStack(alignment: .top) {
            SideMapView(model: model)
              .frame(width: max(64, side * 0.2), height: max(96, side * 0.3))
            Spacer()
            orientationBadge
          }
          Spacer()
          readout
        }
        .padding(12)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 8)
          .onChanged { value in
            if dragStartOffset == nil { dragStartOffset = model.offsetMM }
            let mmPerPoint = Double(ViewerModel.sliceFOV.y) / Double(side)
            model.offsetMM = min(max((dragStartOffset ?? 0) - value.translation.height * mmPerPoint, -80), 80)
          }
          .onEnded { _ in dragStartOffset = nil }
      )
    }
    .sensoryFeedback(.selection, trigger: detent)
    .sensoryFeedback(.impact(weight: .light), trigger: model.selectedFindingID)
  }

  private var accessibilityLabel: String {
    var text = "Cross-section. \(model.viewDescription)."
    if let finding = model.selectedFinding { text += " Centred on \(finding.title)." }
    if model.mode == .ct { text += " Showing grayscale CT." }
    return text
  }

  private var orientationBadge: some View {
    VStack(alignment: .trailing, spacing: 4) {
      Text(model.tilt < 45 ? "Front" : "Head")
        .font(.caption2.weight(.semibold))
      Image(systemName: "arrow.up")
        .font(.caption2.weight(.bold))
    }
    .foregroundStyle(.white.opacity(0.7))
    .padding(8)
    .background(.black.opacity(0.4), in: .rect(cornerRadius: 10))
    .accessibilityHidden(true)
  }

  private var readout: some View {
    HStack(spacing: 10) {
      Image(systemName: model.isHingeDriving ? "iphone.gen3" : "slider.horizontal.3")
        .symbolEffect(.pulse, isActive: model.isHingeDriving)
      VStack(alignment: .leading, spacing: 2) {
        Text(model.viewDescription)
          .font(.subheadline.weight(.semibold))
        Group {
          if let angle = model.hingeAngle {
            Text("Hinge \(Int(angle.rounded()))° · cut tilted \(Int(model.tilt.rounded()))°")
          } else if model.deviceHasHinge {
            Text("Fold the phone to tilt the cut")
          } else {
            Text("Cut tilted \(Int(model.tilt.rounded()))° · drag to move \(Int(model.offsetMM.rounded())) mm")
          }
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.75))
      }
      Spacer(minLength: 0)
      Text(model.mode == .ct ? "CT" : "Layers")
        .font(.caption.weight(.bold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.18), in: .capsule)
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(.ultraThinMaterial.opacity(0.9), in: .rect(cornerRadius: 14))
    .environment(\.colorScheme, .dark)
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private func markers(size: CGSize) -> some View {
    let plane = model.plane
    let pxPerMM = size.width / CGFloat(ViewerModel.sliceFOV.x)
    let all: [(offset: Int, element: Finding)] = Array(model.scanCase.findings.enumerated())
    let selectedID: Finding.ID? = model.selectedFindingID
    let others: [(offset: Int, element: Finding)] = all.filter { $0.element.id != selectedID }
    let chosen: [(offset: Int, element: Finding)] = all.filter { $0.element.id == selectedID }
    let ordered: [(offset: Int, element: Finding)] = others + chosen
    ForEach(ordered, id: \.element.id) { index, finding in
      let distance = abs(plane.distance(to: finding.anchorMM))
      let radius = max(CGFloat(finding.sizeMM ?? 12) / 2, 6)
      if distance < Float(radius) + 10 {
        let point = plane.imagePoint(of: finding.anchorMM, imageSize: size)
        let selected = finding.id == model.selectedFindingID
        let r = radius * pxPerMM + (selected ? 10 : 6)
        ZStack {
          Circle()
            .stroke(selected ? Color.accentColor : .white, style: StrokeStyle(lineWidth: selected ? 3 : 1.5, dash: selected ? [] : [4, 3]))
            .frame(width: r * 2, height: r * 2)
            .shadow(color: .black.opacity(0.6), radius: 3)
          Text("\(index + 1)")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(5)
            .background(selected ? Color.accentColor : .black.opacity(0.6), in: .circle)
            .offset(x: r * 0.75, y: -r * 0.75)
        }
        .position(point)
        .opacity(Double(max(0.35, 1 - distance / (Float(radius) + 10))))
        .onTapGesture { model.select(finding) }
        .accessibilityHidden(true)
      }
    }
  }
}
