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
                self.error = Self.friendlyMessage(for: error)
                stage = .failed
            }
        }
    }

    func cancel() { task?.cancel() }

    var stageText: String {
        switch stage {
        case .downloading: "Downloading scan…"
        case .decoding: "Decoding scan…"
        case .preparing: "Preparing 3D…"
        case .ready: "Ready"
        case .failed: "Failed"
        }
    }

    /// CatalogError/VolumeLoader errors already read as plain sentences (see CatalogError);
    /// anything else (raw NSError/system text) gets a generic, human fallback instead.
    private static func friendlyMessage(for error: Error) -> String {
        let raw = error.localizedDescription
        if raw.isEmpty || raw.contains("Error Domain=") || raw.contains("NSError") || raw.contains("NS%") {
            return "Couldn't load this scan. Check your connection and try again."
        }
        return raw
    }

    var progress: Double? {
        switch stage {
        case .downloading: CaseCatalog.shared.downloads[info.id]
        case .decoding: decodeProgress > 0 ? decodeProgress : nil
        default: nil
        }
    }
}

// Library layout follows the BodyMaps web library (PanTS-Demo, read from source):
// - src/routes/Homepage/components/CaseGrid/index.tsx — `grid gap-4 grid-cols-2` of
//   Preview cards on narrow screens; mirrored by the 2-column LazyVGrid below.
// - src/components/Preview.tsx — thumbnail on top (object-contain on black), corner action
//   badges absolutely positioned over the image, then a `p-3` body: bold case title, then a
//   meta row whose finding label is colour-coded (tumor red). CaseCard keeps that order.
// - src/routes/Homepage/components/LibraryHeader/index.tsx — a plain section title
//   ("Browse Library") with actions on the right; our header is "Cases" + count.
// Deviation: the first case (CaseCatalog.heroOrder, the head CT with the AI result) is a
// full-width hero card, because it is the demo's entry point and its finding needs room.
struct LibraryView: View {
    var autoOpenID: String? = nil

    @State private var session: CaseSession?
    @State private var loaded = false
    @State private var didAutoOpen = false
    @State private var query = ""

    private var catalog: CaseCatalog { CaseCatalog.shared }
    private var filtered: [CaseInfo] { catalog.filtered(query) }

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
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await catalog.refresh() }
        }
        .task {
            // Bundled cases are already listed synchronously; open before the network refresh.
            autoOpenIfNeeded()
            await catalog.refresh()
            loaded = true
            autoOpenIfNeeded()
        }
        .fullScreenCover(item: $session) { s in
            CaseSessionView(session: s) { session = nil }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Theme.accent, Theme.volumeColor],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("GENERALIZABLE").font(Theme.ui(11, .bold)).tracking(1.4)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if catalog.isRefreshing {
                    ProgressView().controlSize(.mini).tint(Theme.textTertiary)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Cases").font(.system(size: 34, weight: .bold)).foregroundStyle(Theme.text)
                Spacer()
                (Text("\(catalog.cases.count)").font(Theme.mono(13, .semibold)).foregroundStyle(Theme.textSecondary)
                    + Text(catalog.cases.count == 1 ? " study" : " studies").font(Theme.ui(13)).foregroundStyle(Theme.textTertiary))
            }
            Text("CT · on-device 3D · AI findings")
                .font(Theme.ui(13, .medium)).foregroundStyle(Theme.textTertiary)
            Text("Demo · public research data · not a diagnosis")
                .font(Theme.mono(10.5)).foregroundStyle(Theme.textTertiary)
        }
        .padding(.top, Theme.Space.m)
    }

    private var searchField: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textTertiary)
            TextField("Search by case number, region, finding", text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(Theme.ui(15))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Space.m).frame(height: 40)
        .gzCard(radius: Theme.Radius.control + 3)
    }

    // Demo cases (bundled: instant, no download) are grouped above the downloadable
    // BodyMaps catalog so it's clear at a glance what opens instantly vs. what fetches
    // over the network. The head CT (CaseCatalog.heroID) stays the hero, as before.
    @ViewBuilder private var content: some View {
        let list = filtered
        if catalog.cases.isEmpty {
            emptyState(icon: loaded ? "tray" : nil,
                       title: loaded ? "No cases available" : "Loading catalog",
                       detail: loaded ? (catalog.errors[""] ?? "Pull to refresh") : nil)
        } else if list.isEmpty {
            emptyState(icon: "magnifyingglass", title: "No matches for “\(query)”",
                       detail: "Try a case number like 8205")
        } else if !query.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                sectionLabel("Results")
                grid(list)
            }
        } else {
            let bundled = list.filter(\.isBundled)
            let remote = list.filter { !$0.isBundled }
            let hero = bundled.first
            let demoRest = hero == nil ? bundled : Array(bundled.dropFirst())
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                if let hero {
                    Button { open(hero) } label: {
                        CaseCard(info: hero, download: catalog.downloads[hero.id], hero: true)
                    }
                    .buttonStyle(PressableCardStyle())
                }
                if !demoRest.isEmpty {
                    sectionLabel("Demo cases", detail: "Bundled with the app — open instantly, no download.")
                    grid(demoRest)
                }
                if !remote.isEmpty {
                    sectionLabel("BodyMaps catalog",
                                 detail: "\(remote.count) studies from the BodyMaps research dataset · downloads when opened")
                    grid(remote)
                }
            }
        }
    }

    private func grid(_ items: [CaseInfo]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: Theme.Space.m)],
                  spacing: Theme.Space.m) {
            ForEach(items) { c in
                Button { open(c) } label: {
                    CaseCard(info: c, download: catalog.downloads[c.id])
                }
                .buttonStyle(PressableCardStyle())
            }
        }
    }

    private func sectionLabel(_ t: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t.uppercased()).font(Theme.ui(11, .semibold)).tracking(0.8)
                .foregroundStyle(Theme.textTertiary)
            if let detail {
                Text(detail).font(Theme.ui(12)).foregroundStyle(Theme.textTertiary.opacity(0.85))
            }
        }
        .padding(.top, Theme.Space.xs)
    }

    private func emptyState(icon: String?, title: String, detail: String?) -> some View {
        VStack(spacing: Theme.Space.m) {
            if let icon {
                Image(systemName: icon).font(.system(size: 34, weight: .light))
            } else {
                ProgressView().controlSize(.large)
            }
            Text(title).font(Theme.ui(15, .medium)).multilineTextAlignment(.center)
            if let detail {
                Text(detail).font(Theme.ui(12)).foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity).padding(.top, 100)
    }

    private func open(_ c: CaseInfo) {
        let s = CaseSession(info: c)
        session = s
        s.start()
    }

    private func autoOpenIfNeeded() {
        guard !didAutoOpen, let id = autoOpenID else { return }
        if let c = catalog.cases.first(where: { $0.id == id || $0.id.hasSuffix(id) }) {
            didAutoOpen = true
            open(c)
        }
    }
}

private struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// "AI" badge (sparkles + headline), shown when the case folder has ai.json.
struct AIBadge: View {
    var text: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles").font(.system(size: 9, weight: .bold))
            Text("AI").font(Theme.ui(10.5, .heavy))
            if let text {
                Text(text).font(Theme.mono(10, .semibold)).opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8).frame(height: 22)
        .background(Capsule().fill(LinearGradient(colors: [Theme.volumeColor, Theme.accent],
                                                  startPoint: .leading, endPoint: .trailing)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
        .shadow(color: Theme.volumeColor.opacity(0.35), radius: 6, y: 2)
    }
}

private struct CaseCard: View {
    var info: CaseInfo
    var download: Double?
    var hero = false

    private var isLocal: Bool { info.isBundled || info.ctURL?.isFileURL == true }
    private var region: String { info.metadata["region"] ?? CaseCatalog.region(for: info.id) }
    private var name: String { info.metadata["name"] ?? CaseCatalog.shortName(info.id) }
    private var finding: String? { info.metadata["finding"] }
    private var ai: String? { info.metadata["ai"] }

    /// Bundled cases with no local profile.jpg (e.g. the synthetic Sun/Circuit board demo
    /// cases) fall through to a placeholder — never attempt a network fetch that would
    /// only 404, since these ids don't exist in the remote catalog.
    private var displayThumbnailURL: URL? {
        if info.isBundled && info.thumbnailURL?.isFileURL != true { return nil }
        return info.thumbnailURL
    }
    private var fallback: (symbol: String, tint: Color) { CaseThumbnail.fallback(for: info) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color.black
                CaseThumbnail(url: displayThumbnailURL, fallbackSymbol: fallback.symbol, fallbackTint: fallback.tint)
            }
            .frame(height: hero ? 210 : 150).frame(maxWidth: .infinity)
            .clipped()
            .overlay(LinearGradient(colors: [.clear, Theme.surface.opacity(0.85)],
                                    startPoint: .init(x: 0.5, y: 0.55), endPoint: .bottom))
            .overlay(alignment: .topLeading) {
                if ai != nil { AIBadge(text: hero ? ai : nil).padding(8) }
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: isLocal ? "checkmark.circle.fill" : "icloud.and.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isLocal ? Theme.success : Theme.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.black.opacity(0.55)))
                    .padding(8)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(region.uppercased())
                    .font(Theme.ui(10, .bold)).tracking(0.8)
                    .foregroundStyle(region == "Head CT" ? Theme.volumeColor : Theme.accent)
                Text(name)
                    .font(Theme.ui(hero ? 20 : 15, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                if let finding {
                    HStack(spacing: 5) {
                        Circle().fill(Organ.hemorrhage.color).frame(width: 6, height: 6)
                        Text(finding).font(Theme.ui(hero ? 13 : 11.5, .medium))
                            .foregroundStyle(Theme.text.opacity(0.85)).lineLimit(1)
                    }
                } else {
                    Text(info.id).font(Theme.mono(10.5)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
                if hero, info.metadata["aiModel"] != nil {
                    Text("AI detection model").font(Theme.ui(11, .medium)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
                if let d = download {
                    HStack(spacing: 6) {
                        ProgressView(value: d).tint(Theme.accent)
                        Text("\(Int(d * 100))%").font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.m - 2)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                ViewerView(state: v, onClose: close)
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
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
