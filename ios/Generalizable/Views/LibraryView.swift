// Case library (OHIF's "study list" / work list equivalent). Owned by agent shell.
// Tapping a case: CaseCatalog.ensureLocal → VolumeLoader.load (LoadingView) → ViewerView.
import SwiftUI

/// One open-case attempt: download, decode, then hand a ViewerState to the viewer.
@MainActor @Observable
final class CaseSession: Identifiable {
    enum Stage { case downloading, decoding, preparing, ready, failed }
    let id = UUID()
    private(set) var info: CaseInfo
    var stage: Stage = .downloading
    var decodeProgress: Double = 0
    var error: String?
    var viewer: ViewerState?
    private var task: Task<Void, Never>?

    init(info: CaseInfo) { self.info = info }

    func start() {
        task?.cancel()
        error = nil
        stage = .downloading
        decodeProgress = 0
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let local = try await CaseCatalog.shared.ensureLocal(info)
                try Task.checkCancellation()
                info = local
                stage = .decoding
                let loaded = try await VolumeLoader.load(local) { p in
                    Task { @MainActor [weak self] in self?.decodeProgress = p }
                }
                try Task.checkCancellation()
                stage = .preparing
                await Task.yield()
                viewer = ViewerState(loaded: loaded)
                stage = .ready
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
                stage = .failed
            }
        }
    }

    func cancel() { task?.cancel() }

    var stageText: String {
        switch stage {
        case .downloading: "Downloading scan"
        case .decoding: "Decoding volume"
        case .preparing: "Preparing viewer"
        case .ready: "Ready"
        case .failed: "Failed"
        }
    }

    var progress: Double? {
        switch stage {
        case .downloading: CaseCatalog.shared.downloads[info.id]
        case .decoding: decodeProgress > 0 ? decodeProgress : nil
        default: nil
        }
    }
}

struct LibraryView: View {
    var autoOpenID: String? = nil

    @State private var session: CaseSession?
    @State private var loaded = false
    @State private var didAutoOpen = false
    @State private var query = ""

    private var catalog: CaseCatalog { CaseCatalog.shared }

    private var filtered: [CaseInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return catalog.cases }
        return catalog.cases.filter {
            $0.id.lowercased().contains(q) || $0.title.lowercased().contains(q)
                || $0.metadata.values.contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    header
                    searchField
                    content
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.bottom, Theme.Space.xxl)
            }
            .scrollIndicators(.hidden)
            .refreshable { await catalog.refresh() }
        }
        .task {
            await catalog.refresh()
            loaded = true
            autoOpenIfNeeded()
        }
        .fullScreenCover(item: $session) { s in
            CaseSessionView(session: s) { session = nil }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: [Theme.accent, Theme.volumeColor],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("Generalizable").font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                }
                Text("One viewer for anything you can slice")
                    .font(Theme.ui(13, .medium)).foregroundStyle(Theme.textSecondary)
                Text("Demo · public research data · not a diagnosis")
                    .font(Theme.mono(10.5)).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
        .padding(.top, Theme.Space.l)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Theme.ui(15, .semibold)).foregroundStyle(Theme.text)
            Spacer()
            Text("\(count)").font(Theme.mono(12, .semibold)).foregroundStyle(Theme.textTertiary)
        }
        .padding(.top, Theme.Space.s)
    }

    private func grid(_ cases: [CaseInfo]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 158, maximum: 260), spacing: Theme.Space.m)],
                  spacing: Theme.Space.m) {
            ForEach(cases) { c in
                Button { open(c) } label: {
                    CaseCard(info: c, download: catalog.downloads[c.id])
                }
                .buttonStyle(PressableCardStyle())
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textTertiary)
            TextField("Search cases", text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(Theme.ui(15))
        }
        .padding(.horizontal, Theme.Space.m).frame(height: 40)
        .gzCard(radius: Theme.Radius.control + 3)
    }

    @ViewBuilder private var content: some View {
        if catalog.cases.isEmpty {
            VStack(spacing: Theme.Space.m) {
                if loaded {
                    Image(systemName: "tray").font(.system(size: 34, weight: .light))
                    Text("No cases available").font(Theme.ui(15, .medium))
                    Text("Pull to refresh").font(Theme.ui(12)).foregroundStyle(Theme.textTertiary)
                } else {
                    ProgressView().controlSize(.large)
                    Text("Loading catalog").font(Theme.ui(13))
                }
            }
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity).padding(.top, 120)
        } else {
            // Bundled demo cases first, apart from the thousands of downloadable catalog cases.
            let local = filtered.filter(\.isBundled)
            let remote = filtered.filter { !$0.isBundled }
            if !local.isEmpty {
                sectionHeader("Ready offline", count: local.count)
                grid(local)
            }
            if !remote.isEmpty {
                sectionHeader("BodyMaps catalog · downloads on open", count: remote.count)
                grid(remote)
            }
        }
    }

    private func open(_ c: CaseInfo) {
        let s = CaseSession(info: c)
        session = s
        s.start()
    }

    private func autoOpenIfNeeded() {
        guard !didAutoOpen, let id = autoOpenID else { return }
        didAutoOpen = true
        if let c = catalog.cases.first(where: { $0.id == id || $0.id.hasSuffix(id) }) { open(c) }
    }
}

private struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

private struct CaseCard: View {
    var info: CaseInfo
    var download: Double?

    /// One readable line instead of three truncated chips: the finding if the case has one,
    /// else the AI headline, else demographics.
    private var detail: (text: String, alert: Bool)? {
        let m = info.metadata
        if let f = m["finding"], !f.isEmpty { return (f, true) }
        if let a = m["ai"], !a.isEmpty { return (a, false) }
        if let o = m["organs"], !o.isEmpty { return ("\(o) organs segmented", false) }
        let demo = [m["sex"], m["age"].map { "\($0) y" }, m["phase"]].compactMap { $0 }.filter { !$0.isEmpty }
        return demo.isEmpty ? nil : (demo.joined(separator: " · "), false)
    }

    private var isLocal: Bool { info.isBundled || info.ctURL?.isFileURL == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                CaseThumbnail(url: info.thumbnailURL)
                    .frame(height: 150).frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(LinearGradient(colors: [.clear, Theme.surface.opacity(0.9)],
                                            startPoint: .center, endPoint: .bottom))
                Image(systemName: isLocal ? "checkmark.circle.fill" : "icloud.and.arrow.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isLocal ? Theme.success : Theme.textSecondary)
                    .padding(6).background(Circle().fill(.ultraThinMaterial))
                    .padding(8)
            }
            VStack(alignment: .leading, spacing: 6) {
                // Region and short name on separate lines: "Head CT · CQ500-243" truncated on one.
                Text(info.metadata["region"] ?? info.title)
                    .font(Theme.ui(15, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(info.metadata["name"] ?? info.id)
                    .font(Theme.mono(11)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                if let d = detail {
                    HStack(spacing: 6) {
                        if d.alert { Circle().fill(Color.red).frame(width: 7, height: 7) }
                        Text(d.text).font(Theme.ui(12, .medium))
                            .foregroundStyle(d.alert ? Theme.text : Theme.textSecondary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let d = download {
                    HStack(spacing: 6) {
                        ProgressView(value: d).tint(Theme.accent)
                        Text("\(Int(d * 100))%").font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)   // equal card heights
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .gzCard()
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

/// Full-screen cover content: loading → viewer.
private struct CaseSessionView: View {
    @Bindable var session: CaseSession
    var close: () -> Void

    var body: some View {
        ZStack {
            if let v = session.viewer {
                ViewerView(state: v).transition(.opacity)
            } else {
                LoadingView(info: session.info, stage: session.stageText, progress: session.progress,
                            error: session.error,
                            onCancel: { session.cancel(); close() },
                            onRetry: { session.start() })
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: session.viewer != nil)
    }
}
