import SwiftUI

/// A single, bounded workspace. The model gets the screen; supporting information lives in sheets.
struct ImmersiveExplorerView: View {
  @State private var session = ExplorerSession()
  @State private var inspector: ExplorerInspectorSection?
  @State private var showsLibrary = false
  @State private var showsReport = false
  @State private var showsExpandedSlice = false
  @Environment(\.horizontalSizeClass) private var widthClass
  @Environment(\.dynamicTypeSize) private var textSize

  var body: some View {
    NavigationStack {
      Group {
        if #available(iOS 27.1, *) {
          workspace.onHingeChange { _, context in
            session.updateHinge(angle: context.hinge?.angle.degrees,
              partiallyOpen: context.hinge?.status == .partiallyOpen)
          }
        } else {
          workspace
        }
      }
      .background(ExplorerPalette.background)
      .navigationTitle("Generalizable")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Picker("Subject", selection: Binding(get: { session.subject }, set: session.selectSubject)) {
            ForEach(ExplorerSubject.allCases) { subject in
              Label(subject.title, systemImage: subject.symbol).tag(subject)
            }
          }
          .pickerStyle(.menu)
        }
        if widthClass == .regular {
          ToolbarItem(placement: .topBarLeading) {
            Picker("View", selection: modeSelection) {
              ForEach(ExplorerHingeMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.menu)
          }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button("Case library", systemImage: "folder") { showsLibrary = true }
          Button("Report glossary", systemImage: "text.document") { showsReport = true }
          Button("Reset view", systemImage: "arrow.counterclockwise") { session.reset() }
          Button("How to explore", systemImage: "info") { inspector = .help }
        }
      }
      .sheet(item: $inspector) { section in
        ExplorerInspectorView(session: session, section: section)
          .presentationDetents([.medium, .large])
          .presentationDragIndicator(.visible)
      }
      .sheet(isPresented: $showsLibrary) { CaseLibraryView(showsDoneButton: true) }
      .sheet(isPresented: $showsReport) { ReportReaderView() }
      .sheet(isPresented: $showsExpandedSlice) { ExplorerExpandedSliceView(session: session) }
      .onChange(of: session.renderKey, initial: true) { session.requestRender() }
      .sensoryFeedback(.selection, trigger: session.hingeMode)
      .sensoryFeedback(.selection, trigger: session.pointIndex)
    }
    .tint(ExplorerPalette.mint)
    .preferredColorScheme(.dark)
  }

  private var workspace: some View {
    VStack(spacing: 0) {
      if widthClass != .regular {
        modePicker
          .padding(.horizontal, 16)
          .padding(.top, 8)
          .padding(.bottom, 10)
      }
      stage
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder private var modePicker: some View {
    if textSize.isAccessibilitySize {
      Picker("View", selection: modeSelection) {
        ForEach(ExplorerHingeMode.allCases) { mode in Text(mode.title).tag(mode) }
      }
      .pickerStyle(.menu)
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      Picker("View", selection: modeSelection) {
        ForEach(ExplorerHingeMode.allCases) { mode in Text(mode.title).tag(mode) }
      }
      .pickerStyle(.segmented)
    }
  }

  private var modeSelection: Binding<ExplorerHingeMode> {
    Binding(get: { session.hingeMode }, set: session.selectHingeMode)
  }

  @ViewBuilder private var stage: some View {
    if widthClass == .regular, session.hingeMode != .volume {
      if #available(iOS 27.1, *) {
        ArrangementView {
          VStack(spacing: 0) {
            if session.hingeMode == .hingeSlice { slicePane(reference: true) } else { volumePane }
            dock
          }
        } secondary: {
          slicePane(reference: false)
        }
        .arrangementViewStyle(.split)
        .background(canvasBackground)
      } else {
        compactStage
      }
    } else {
      compactStage
    }
  }

  private var compactStage: some View {
    VStack(spacing: 0) {
      if session.hingeMode == .hingeSlice {
        GeometryReader { geometry in
          if geometry.size.width > geometry.size.height {
            HStack(spacing: 1) {
              slicePane(reference: true)
              slicePane(reference: false)
            }
          } else {
            VStack(spacing: 1) {
              slicePane(reference: false)
              slicePane(reference: true)
            }
          }
        }
      } else {
        volumePane
      }
      dock
    }
    .background(canvasBackground)
  }

  private var volumePane: some View {
    GeometryReader { geometry in
      VolumeSceneView(subject: session.subject.rawValue, selectedAnchor: session.cutAnchor,
        tiltDegrees: session.cutAngle, sliceOffset: session.cutOffset, visibleLayers: session.visibleLayers,
        showsCutPlane: session.hingeMode == .layerHeight, showsMarker: session.hingeMode == .hingeSlice)
        .id("\(session.subject.rawValue)-\(session.cameraReset)")
        .frame(width: geometry.size.width, height: geometry.size.height)
        .accessibilityLabel("\(session.subject.title), three-dimensional model")
        .accessibilityValue(session.hingeMode == .layerHeight ? "Horizontal slice at \(Int(session.layerHeight)) millimeters" : "\(session.visibleLayers.count) visible layers")
        .overlay(alignment: .topLeading) {
          VStack(alignment: .leading, spacing: 5) {
            Text(session.subject.title).font(.title3.weight(.semibold))
            Text(session.subject == .patient ? "Synthetic teaching model" : "Illustrative model")
              .font(.caption).foregroundStyle(.secondary)
          }
          .padding(20)
          .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
          if session.hingeMode == .layerHeight, widthClass != .regular {
            Button { showsExpandedSlice = true } label: {
              SliceCanvasView(session: session, isThumbnail: true)
                .frame(width: min(116, geometry.size.width * 0.32), height: min(116, geometry.size.height * 0.4))
                .overlay(alignment: .bottom) {
                  Text("Expand").font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .padding(6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Expand horizontal slice")
            .padding(14)
          }
        }
    }
    .frame(minWidth: 0, minHeight: 0)
    .clipped()
  }

  private func slicePane(reference: Bool) -> some View {
    VStack(spacing: 8) {
      HStack {
        Text(reference ? "Reference" : (session.hingeMode == .layerHeight ? "Horizontal slice" : "Hinge slice"))
          .font(.subheadline.weight(.semibold))
        Spacer(minLength: 4)
        Text(sliceReadout(reference: reference))
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(ExplorerPalette.mint)
      }
      SliceCanvasView(session: session, isReference: reference, showsAnnotations: false)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .padding(16)
    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    .background(ExplorerPalette.background.opacity(0.55))
  }

  private var dock: some View {
    VStack(spacing: 12) {
      if !textSize.isAccessibilitySize {
        ExplorerAdjustmentBar(session: session)
      }
      HStack(spacing: 10) {
        Button { inspector = .finding } label: {
          HStack(spacing: 8) {
            Circle().fill(ExplorerPalette.mint).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 3) {
              Text(session.point.title).font(.subheadline.weight(.semibold))
              Text("\(session.point.measurement) · \(session.subject == .patient ? "Teaching scan" : "Illustrative model")")
                .font(.caption).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
          }
          .padding(.vertical, 8)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Learn about \(session.point.title), \(session.point.measurement)")
        Button("Layers", systemImage: "square.stack.3d.up") { inspector = .layers }
          .labelStyle(.iconOnly)
          .buttonStyle(.bordered)
          .controlSize(.large)
        Button("Adjust", systemImage: "slider.horizontal.3") { inspector = .controls }
          .labelStyle(.iconOnly)
          .buttonStyle(.bordered)
          .controlSize(.large)
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 12)
    .background(.regularMaterial)
  }

  private func sliceReadout(reference: Bool) -> String {
    guard let frame = reference ? session.referenceFrame : session.frame else { return "Preparing…" }
    if let height = frame.height { return "\(Int(height)) mm" }
    return "\(Int(frame.angle.rounded()))°"
  }

  private var canvasBackground: some View {
    RadialGradient(colors: [Color(red: 0.055, green: 0.14, blue: 0.19), ExplorerPalette.background],
      center: .center, startRadius: 10, endRadius: 600)
      .ignoresSafeArea()
  }
}

enum ExplorerPalette {
  static var background: Color { Color(red: 0.025, green: 0.045, blue: 0.07) }
  static var surface: Color { Color(red: 0.065, green: 0.09, blue: 0.12) }
  static var mint: Color { Color(red: 0.46, green: 0.94, blue: 0.81) }
  static func layerColor(_ layer: TissueLayer) -> Color {
    let c = layer.rgba
    return Color(red: Double(c.x) / 255, green: Double(c.y) / 255, blue: Double(c.z) / 255)
  }
}
