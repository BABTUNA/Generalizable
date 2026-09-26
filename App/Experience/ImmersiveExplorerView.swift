import SwiftUI

struct ImmersiveExplorerView: View {
  @State private var session = ExplorerSession()
  @State private var showsReport = false
  @State private var showsHelp = false
  @Environment(\.horizontalSizeClass) private var widthClass
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    NavigationStack {
      Group {
        if #available(iOS 27.1, *) {
          adaptiveContent
            .onHingeChange { _, context in
              session.updateHinge(angle: context.hinge?.angle.degrees, partiallyOpen: context.hinge?.status == .partiallyOpen)
            }
        } else {
          adaptiveContent
        }
      }
      .background(ExplorerPalette.background)
      .navigationTitle("Generalizable")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Picker("Explore a subject", selection: Binding(get: { session.subject }, set: { session.selectSubject($0) })) {
            ForEach(ExplorerSubject.allCases) { subject in
              Label(subject.title, systemImage: subject.symbol).tag(subject)
            }
          }
          .pickerStyle(.menu)
          .tint(ExplorerPalette.mint)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button("Report glossary", systemImage: "text.document") { showsReport = true }
          Button("Reset view", systemImage: "arrow.counterclockwise") { session.reset() }
          Button("How to explore", systemImage: "info") { showsHelp = true }
        }
      }
      .sheet(isPresented: $showsReport) { ReportReaderView() }
      .sheet(isPresented: $showsHelp) { helpSheet }
      .onChange(of: session.renderKey, initial: true) { session.requestRender() }
      .sensoryFeedback(.selection, trigger: session.pointIndex)
    }
    .tint(ExplorerPalette.mint)
    .preferredColorScheme(.dark)
  }

  @ViewBuilder private var adaptiveContent: some View {
    if widthClass == .regular {
      if #available(iOS 27.1, *) {
        ArrangementView {
          controlScroll
        } secondary: {
          visualPanel(expanded: true)
            .padding(20)
        }
        .arrangementViewStyle(.split)
      } else {
        HStack(spacing: 16) {
          visualPanel(expanded: true)
          controlScroll
        }
      }
    } else {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          header
          visualPanel(expanded: false)
          if session.hingeMode == .hingeSlice { referencePanel }
          controls
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity)
      }
    }
  }

  private var controlScroll: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if session.hingeMode == .hingeSlice {
          referencePanel
        } else {
          header
        }
        controls
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var referencePanel: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("BASE PLANE / REFERENCE")
          .font(.system(.caption2, design: .monospaced, weight: .semibold))
          .tracking(1)
        Spacer()
        Image(systemName: "scope")
      }
      .foregroundStyle(ExplorerPalette.mint)
      SliceCanvasView(session: session, isReference: true)
        .frame(height: 240)
      Text("Two cuts. One location.")
        .font(.subheadline.weight(.semibold))
      Text("This plane stays flat while the other turns with the hinge. The dashed line is where the two cuts meet.")
        .font(.caption).foregroundStyle(.secondary)
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(ExplorerPalette.surface, in: RoundedRectangle(cornerRadius: 24))
    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(ExplorerPalette.mint.opacity(0.2)))
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 7) {
        Circle().fill(ExplorerPalette.mint).frame(width: 6, height: 6)
        Text("SPATIAL EXPLORER / 01")
          .font(.caption2.weight(.semibold)).tracking(2.2)
      }
      .foregroundStyle(ExplorerPalette.mint)
      Text(session.subject.headline)
        .font(.system(.largeTitle, design: .rounded, weight: .bold))
        .fixedSize(horizontal: false, vertical: true)
      Text(session.subject.subtitle)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }

  private func visualPanel(expanded: Bool) -> some View {
    VStack(spacing: 0) {
      Picker("Hinge behavior", selection: Binding(get: { session.hingeMode }, set: { session.selectHingeMode($0) })) {
        ForEach(ExplorerHingeMode.allCases) { mode in Text(mode.title).tag(mode) }
      }
      .pickerStyle(.segmented)
      .padding(14)
      HStack {
        Label(session.subject == .patient ? "SYNTHETIC ANATOMY" : "ILLUSTRATIVE MODEL", systemImage: "cube.transparent")
          .font(.system(.caption2, design: .monospaced)).tracking(1)
          .foregroundStyle(ExplorerPalette.mint)
        Spacer(minLength: 4)
        Text("3D / LIVE").font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
      }
      .padding(18)

      ZStack(alignment: .bottomTrailing) {
        ExplorerGrid().accessibilityHidden(true)
        if session.showsSlice {
          SliceCanvasView(session: session, isThumbnail: false)
            .padding(28)
        } else {
          VolumeSceneView(subject: session.subject.rawValue, selectedAnchor: session.cutAnchor, tiltDegrees: session.cutAngle, sliceOffset: session.cutOffset, visibleLayers: session.visibleLayers, showsCutPlane: session.hingeMode != .volume, showsMarker: session.hingeMode == .hingeSlice)
            .id("\(session.subject.rawValue)-\(session.cameraReset)")
            .accessibilityLabel("Three dimensional \(session.subject.title) overview")
            .accessibilityValue(session.hingeMode == .volume ? "Centered volume. \(session.visibleLayers.count) visible layers." : "\(session.hingeMode.title). Cut angle \(Int(session.cutAngle)) degrees. Height \(Int(session.cutAnchor.z)) millimeters.")
            .overlay(alignment: .topLeading) {
              VStack(alignment: .leading, spacing: 5) {
                Text(session.point.location.uppercased()).font(.system(.caption2, design: .monospaced))
                Text(session.point.measurement).font(.title3.weight(.semibold)).monospacedDigit()
              }
              .foregroundStyle(.white.opacity(0.78))
              .padding(.horizontal, 18)
              .allowsHitTesting(false)
            }
          if session.hingeMode != .volume { Button {
            withAnimation(reduceMotion ? nil : .snappy) { session.showsSlice = true }
          } label: {
            VStack(alignment: .leading, spacing: 8) {
              HStack(spacing: 5) {
                Text("LIVE SLICE").font(.system(.caption2, design: .monospaced, weight: .semibold))
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption2)
              }
              .foregroundStyle(ExplorerPalette.mint)
              SliceCanvasView(session: session, isThumbnail: true)
                .frame(width: 116, height: 116)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.13)))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Expand live cross-section")
          .padding(12)
          }
        }
      }
      .frame(minHeight: expanded ? 280 : 310, maxHeight: expanded ? .infinity : 340)
      .clipped()

      HStack(spacing: 0) {
        telemetry("MODE", value: session.hingeMode == .volume ? "VOLUME" : "\(Int(session.cutAngle))° CUT")
        Spacer(minLength: 4)
        telemetry("HEIGHT", value: "\(Int(session.cutAnchor.z)) mm")
        Spacer(minLength: 4)
        telemetry(session.hingeMode == .volume ? "SPACE" : "FIELD", value: session.hingeMode == .volume ? "3D" : "400 mm")
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 12)
      .background(.black.opacity(0.15))

      if session.hingeMode != .volume {
        Picker("Visualization", selection: $session.showsSlice) {
          Text("3D overview").tag(false)
          Text("Live cross-section").tag(true)
        }
        .pickerStyle(.segmented)
        .padding(14)
      } else {
        Text(session.hingeMode.description)
          .font(.caption).foregroundStyle(.secondary)
          .padding(14)
      }
    }
    .background(ExplorerPalette.surface, in: RoundedRectangle(cornerRadius: 26))
    .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.08)))
    .clipShape(RoundedRectangle(cornerRadius: 26))
  }

  private var controls: some View {
    VStack(alignment: .leading, spacing: 24) {
      foldControl
      layers
      findings
      explanation
      if session.subject == .patient {
        Button {
          showsReport = true
        } label: {
          HStack(spacing: 14) {
            Image(systemName: "text.document").font(.title2).foregroundStyle(ExplorerPalette.mint)
            VStack(alignment: .leading, spacing: 4) {
              Text("Open the report glossary").font(.subheadline.weight(.semibold))
              Text("Look up terms privately, without saving.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
          }
          .padding(18)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(ExplorerPalette.surface, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
      }
      Text(session.subject == .patient ? "Synthetic teaching scan · Not your anatomy or a diagnosis" : "Illustrative model · Dimensions and spacing simplified")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
  }

  private var foldControl: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 5) {
          Text(session.hingeMode == .volume ? "VOLUMETRIC DISPLAY" : (session.hingeAvailable && session.followsFold ? "HINGE LINKED" : "TOUCH CONTROL"))
            .font(.caption2.weight(.bold)).tracking(1.5)
            .foregroundStyle(ExplorerPalette.mint)
          Text(session.hingeMode.title).font(.headline)
        }
        Spacer(minLength: 8)
        Text(modeReadout)
          .font(.system(.largeTitle, design: .rounded, weight: .light))
          .monospacedDigit()
          .contentTransition(.numericText())
      }

      Text(session.hingeMode.description).font(.subheadline).foregroundStyle(.secondary)

      switch session.hingeMode {
      case .volume:
        Button("Center volume", systemImage: "viewfinder") { session.cameraReset += 1 }
          .buttonStyle(.bordered)
      case .hingeSlice:
        Slider(value: Binding(get: { 180 - session.tiltDegrees }, set: {
          session.followsFold = false
          session.tiltDegrees = 180 - $0
        }), in: 90...180) {
          Text("Hinge angle")
        } minimumValueLabel: {
          Text("90°").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        } maximumValueLabel: {
          Text("180°").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .accessibilityValue("\(Int(180 - session.tiltDegrees)) degree hinge, \(Int(session.tiltDegrees)) degree cut")

        HStack {
          Text("Slice position").font(.subheadline)
          Spacer()
          Text(abs(session.sliceOffset) < 0.5 ? "Through focus" : "\(Int(session.sliceOffset)) mm from focus")
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        Slider(value: $session.sliceOffset, in: -160...160) { Text("Slice position") }
          .accessibilityValue("\(Int(session.sliceOffset)) millimeters from focus")
      case .layerHeight:
        Slider(value: Binding(get: { session.layerHeight }, set: {
          session.followsFold = false
          session.layerHeight = $0
        }), in: 0...576) {
          Text("Layer height")
        } minimumValueLabel: {
          Text("Bottom").font(.caption).foregroundStyle(.secondary)
        } maximumValueLabel: {
          Text("Top").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityValue("\(Int(session.layerHeight)) millimeters from the bottom")
        Text("180° at the bottom · 90° at the top")
          .font(.caption.monospaced()).foregroundStyle(.secondary)
        Button("Return to finding", systemImage: "scope") {
          session.layerHeight = Double(session.point.anchor.z)
          session.followsFold = false
        }
        .buttonStyle(.bordered)
      }

      if session.hingeAvailable && session.hingeMode != .volume {
        Toggle("Follow the fold", isOn: $session.followsFold)
          .font(.subheadline)
          .onChange(of: session.followsFold) {
            if session.followsFold, let angle = session.hingeAngle {
              session.applyHinge(angle)
            }
          }
      }
      if session.subject == .patient && session.hingeMode != .volume {
        Picker("Cross-section appearance", selection: $session.mode) {
          Text("Color layers").tag(RenderOptions.Mode.layers)
          Text("CT scan").tag(RenderOptions.Mode.ct)
        }
        .pickerStyle(.segmented)
      }
    }
    .padding(20)
    .background(ExplorerPalette.mint.opacity(0.055), in: RoundedRectangle(cornerRadius: 24))
    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(ExplorerPalette.mint.opacity(0.2)))
  }

  private var modeReadout: String {
    switch session.hingeMode {
    case .volume: "3D"
    case .hingeSlice: "\(Int(180 - session.tiltDegrees))°"
    case .layerHeight: "\(Int(session.layerHeight)) mm"
    }
  }

  private var layers: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(session.mode == .ct ? "3D model layers" : "Isolate the layers").font(.headline)
        Spacer()
        Text("\(activeLayers.filter { session.visibleLayers.contains($0) }.count) visible").font(.caption).foregroundStyle(.secondary)
      }
      if session.mode == .ct {
        Text("The CT slice keeps all tissues visible for comparison. These controls isolate layers in the 3D overview.")
          .font(.caption).foregroundStyle(.secondary)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(activeLayers) { layer in
            Toggle(isOn: Binding(get: { !session.hiddenLayers.contains(layer) }, set: { visible in
              if visible { session.hiddenLayers.remove(layer) } else { session.hiddenLayers.insert(layer) }
            })) {
              HStack(spacing: 7) {
                Circle().fill(ExplorerPalette.layerColor(layer)).frame(width: 7, height: 7)
                Text(layerTitle(layer)).font(.subheadline.weight(.medium))
              }
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .tint(session.hiddenLayers.contains(layer) ? Color.gray : ExplorerPalette.mint)
            .accessibilityHint(session.subject == .patient ? layer.patientDescription : "Show or hide this region of the model")
          }
        }
        .padding(.vertical, 2)
      }
    }
  }

  private var activeLayers: [TissueLayer] {
    switch session.subject {
    case .patient: TissueLayer.allCases
    case .sun: [.skin, .fat, .muscle, .bone, .blood]
    case .circuit: [.muscle, .organs, .bone, .blood]
    }
  }

  private func layerTitle(_ layer: TissueLayer) -> String {
    switch session.subject {
    case .patient: layer.displayName
    case .sun: SolarVolumeSource.displayName(for: layer)
    case .circuit: CircuitVolumeSource.displayName(for: layer)
    }
  }

  private func telemetry(_ name: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(name).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
      Text(value).font(.system(.caption, design: .monospaced, weight: .medium)).foregroundStyle(ExplorerPalette.mint)
    }
    .accessibilityElement(children: .combine)
  }

  private var findings: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(session.subject == .patient ? "Four things to understand" : "Points of interest").font(.headline)
        Spacer()
        Text("\(session.pointIndex + 1) / \(session.subject.points.count)")
          .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          ForEach(Array(session.subject.points.enumerated()), id: \.element.id) { index, point in
            Button {
              withAnimation(reduceMotion ? nil : .snappy) { session.selectPoint(index) }
            } label: {
              VStack(alignment: .leading, spacing: 12) {
                HStack {
                  Text(String(format: "%02d", index + 1)).font(.system(.caption, design: .monospaced))
                  Spacer()
                  if session.pointIndex == index { Image(systemName: "scope").font(.caption) }
                }
                Text(point.title).font(.subheadline.weight(.semibold))
                Text(point.measurement).font(.caption).foregroundStyle(.secondary)
              }
              .foregroundStyle(session.pointIndex == index ? ExplorerPalette.mint : Color.white)
              .padding(16)
              .frame(width: 156, alignment: .leading)
              .background(session.pointIndex == index ? ExplorerPalette.mint.opacity(0.12) : ExplorerPalette.surface, in: RoundedRectangle(cornerRadius: 18))
              .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(session.pointIndex == index ? ExplorerPalette.mint.opacity(0.5) : Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(session.pointIndex == index ? .isSelected : [])
          }
        }
        .padding(.vertical, 2)
      }
    }
  }

  private var explanation: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("IN PLAIN WORDS").font(.caption2.weight(.bold)).tracking(1.6).foregroundStyle(ExplorerPalette.mint)
      Text(session.point.summary).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
      Text(session.point.detail).font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
      Divider().overlay(.white.opacity(0.05))
      VStack(alignment: .leading, spacing: 7) {
        Text(session.subject == .patient ? "A question for your doctor" : "Something to explore")
          .font(.caption.weight(.semibold)).foregroundStyle(ExplorerPalette.mint)
        Text(session.point.question).font(.subheadline)
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(ExplorerPalette.surface, in: RoundedRectangle(cornerRadius: 24))
  }

  private var helpSheet: some View {
    NavigationStack {
      List {
        Section("Explore from within") {
          Label("Drag the 3D model to turn it around.", systemImage: "hand.draw")
          Label("Select a finding to center the cut on it.", systemImage: "scope")
          Label("Hide tissue layers to reveal what is underneath.", systemImage: "square.stack.3d.up")
          Label("Fold iPhone Duo or use Cut angle to tilt the cross-section.", systemImage: "slider.horizontal.3")
        }
        Section("One viewer. Three worlds.") {
          Text("Use the subject picker to explore a synthetic patient scan, the Sun, or a circuit board. Each is a three-dimensional model with a live cross-section.")
        }
        Section("About the teaching scan") {
          Text("The colored anatomy and CT are synthetic educational illustrations. Imported reports remain separate from this model; the model is never presented as your scan.")
        }
      }
      .navigationTitle("How to explore")
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsHelp = false } } }
    }
    .presentationDetents([.medium, .large])
  }
}

enum ExplorerPalette {
  static var background: Color { Color(red: 0.025, green: 0.043, blue: 0.066) }
  static var surface: Color { Color(red: 0.052, green: 0.075, blue: 0.10) }
  static var mint: Color { Color(red: 0.40, green: 0.94, blue: 0.79) }
  static func layerColor(_ layer: TissueLayer) -> Color {
    let c = layer.rgba
    return Color(red: Double(c.x) / 255, green: Double(c.y) / 255, blue: Double(c.z) / 255)
  }
}

private struct ExplorerGrid: View {
  var body: some View {
    Canvas { context, size in
      for x in stride(from: 12.0, to: size.width, by: 22) {
        for y in stride(from: 12.0, to: size.height, by: 22) {
          context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.white.opacity(0.11)))
        }
      }
    }
  }
}
