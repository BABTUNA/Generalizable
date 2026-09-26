import SwiftUI
import UniformTypeIdentifiers

struct FoldScanView: View {
  @State private var session = FoldScanSession()
  @State private var showsImport = false
  @State private var showsSettings = false
  @State private var showsAbout = false
  @Environment(\.horizontalSizeClass) private var widthClass
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    NavigationStack {
      Group {
        if #available(iOS 27.1, *) {
          workspace.onHingeChange { _, context in
            session.updateHinge(angle: context.hinge?.angle.degrees, isClosed: context.hinge?.status == .closed)
          }
        } else { workspace }
      }
      .background(ScanStyle.background)
      .navigationTitle("Anatomy")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button("Open CT scan", systemImage: "folder") { showsImport = true }
          Button("View controls", systemImage: "slider.horizontal.3") { showsSettings = true }
          Button("About this scan", systemImage: "info") { showsAbout = true }
        }
      }
      .fileImporter(isPresented: $showsImport, allowedContentTypes: [.data]) { result in
        if case .success(let url) = result { Task { await session.load(url) } }
      }
      .sheet(isPresented: $showsSettings) { FoldScanInspector(session: session) }
      .sheet(isPresented: $showsAbout) { FoldScanAboutView(isDemo: session.isDemo) }
      .alert("Couldn’t open scan", isPresented: Binding(get: { session.error != nil }, set: { if !$0 { session.error = nil } })) {
        Button("OK", role: .cancel) { session.error = nil }
      } message: { Text(session.error ?? "") }
      .overlay {
        if session.isLoading {
          ProgressView("Opening CT scan…")
            .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
      }
      .task { if session.volume == nil { await session.loadDemo() } }
      .onChange(of: session.renderKey) { session.requestRender() }
    }
    .tint(ScanStyle.accent)
    .preferredColorScheme(.dark)
  }

  @ViewBuilder private var workspace: some View {
    if widthClass == .regular {
      if #available(iOS 27.1, *) {
        ArrangementView {
          mainPane
        } secondary: {
          VStack(spacing: 0) {
            studyHeader
            locatorCanvas
            Text("Drag the blue line to choose a layer.")
              .font(.caption).foregroundStyle(.secondary).padding(16)
          }
        }
        .arrangementViewStyle(.split)
      } else { HStack(spacing: 1) { locatorCanvas; mainPane } }
    } else { mainPane }
  }

  private var mainPane: some View {
    VStack(spacing: 0) {
      if widthClass != .regular { studyHeader }
      axisPicker.padding(.horizontal, 16).padding(.vertical, 12)
      CTSliceCanvas(frame: session.frame)
        .accessibilityAdjustableAction { direction in
          switch direction { case .increment: session.step(1); case .decrement: session.step(-1); @unknown default: break }
        }
      if widthClass != .regular {
        locatorCanvas
        Text("Drag the blue line to choose a layer.")
          .font(.caption).foregroundStyle(.secondary).padding(8)
      }
      sliceControl
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var studyHeader: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 4) {
        Text(session.studyName).font(.headline).lineLimit(1)
        Text(session.isDemo ? "DEMO STUDY · STORED ON DEVICE" : "LOCAL NIFTI · STORED ON DEVICE")
          .font(.system(size: 9, weight: .medium, design: .monospaced))
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      Text("CT").font(.caption.monospaced().weight(.semibold))
        .foregroundStyle(ScanStyle.accent)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(ScanStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
    }
    .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 4)
  }

  @ViewBuilder private var axisPicker: some View {
    if typeSize.isAccessibilitySize {
      Picker("Cross-section", selection: $session.axis) {
        ForEach([ScanAxis.axial, .coronal, .sagittal]) { axis in Text(axis.title).tag(axis) }
      }.pickerStyle(.menu)
    } else {
      Picker("Cross-section", selection: $session.axis) {
        ForEach([ScanAxis.axial, .coronal, .sagittal]) { axis in Text(axis.title).tag(axis) }
      }.pickerStyle(.segmented)
    }
  }

  private var locatorCanvas: some View {
    CTSliceCanvas(frame: session.frame, overview: true, onScrub: session.scrub)
      .allowsHitTesting(session.frame?.key.axis == session.axis)
      .accessibilityAdjustableAction { direction in
        switch direction { case .increment: session.step(1); case .decrement: session.step(-1); @unknown default: break }
      }
  }

  private var sliceControl: some View {
    VStack(spacing: 5) {
      HStack {
        Text("Layer \(session.sliceIndex + 1)")
          .font(.subheadline.weight(.medium)).monospacedDigit()
        Text("of \(session.sliceCount)").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Toggle("Follow fold", isOn: Binding(get: { session.followsFold }, set: session.setFollowsFold))
          .toggleStyle(.button).font(.caption.weight(.medium))
      }
    }
    .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 10)
  }
}
