// Case loading screen (download → decode). Owned by agent shell.
import SwiftUI

struct LoadingView: View {
    var info: CaseInfo
    var stage: String
    /// 0...1, or nil for indeterminate.
    var progress: Double?
    var error: String?
    var onCancel: () -> Void
    var onRetry: (() -> Void)? = nil

    @State private var spin = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            CaseThumbnail(url: info.thumbnailURL)
                .blur(radius: 40).opacity(0.35).ignoresSafeArea()
            LinearGradient(colors: [Theme.bg.opacity(0.2), Theme.bg], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: Theme.Space.xl) {
                Spacer()
                ring
                VStack(spacing: Theme.Space.s) {
                    Text(info.title).font(Theme.ui(20, .semibold)).foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                    Text(info.id).font(Theme.mono(12)).foregroundStyle(Theme.textSecondary)
                    if let f = info.metadata["finding"] {
                        GeneralizableChip(text: f, tint: Theme.text)
                    }
                }
                if let error {
                    VStack(spacing: Theme.Space.m) {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.ui(13, .medium)).foregroundStyle(Theme.danger)
                            .multilineTextAlignment(.center).padding(.horizontal, Theme.Space.xl)
                        if let onRetry {
                            Button("Retry", action: onRetry).buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    Text(stage).font(Theme.ui(13, .medium)).foregroundStyle(Theme.textSecondary)
                        .contentTransition(.opacity)
                }
                Spacer()
                Button(action: onCancel) {
                    Label(error == nil ? "Cancel" : "Back", systemImage: error == nil ? "xmark" : "chevron.left")
                        .font(Theme.ui(15, .semibold)).foregroundStyle(Theme.text)
                        .frame(maxWidth: 220).frame(height: 44)
                        .background(Capsule().fill(Theme.surfaceHi))
                        .overlay(Capsule().strokeBorder(Theme.stroke))
                }
                .buttonStyle(.plain)
                .padding(.bottom, Theme.Space.l)
            }
        }
        .onAppear { spin = true }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Theme.stroke, lineWidth: 6)
            if let p = progress {
                Circle().trim(from: 0, to: max(0.02, min(p, 1)))
                    .stroke(AngularGradient(colors: [Theme.accent.opacity(0.4), Theme.accent], center: .center),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.25), value: p)
                Text("\(Int((p * 100).rounded()))%")
                    .font(Theme.mono(22, .semibold)).foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
            } else {
                Circle().trim(from: 0, to: 0.28)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spin)
                Image(systemName: CaseThumbnail.fallback(for: info).symbol)
                    .font(.system(size: 30)).foregroundStyle(Theme.accent)
            }
        }
        .frame(width: 120, height: 120)
    }
}

/// Loads a thumbnail from a local file URL off the main thread, or remotely via AsyncImage.
/// When there is no image (missing locally, or the remote fetch fails) it shows a tasteful
/// icon placeholder instead of a blank/broken image.
struct CaseThumbnail: View {
    var url: URL?
    var fallbackSymbol: String = "lungs.fill"
    var fallbackTint: Color = Theme.textTertiary
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let url, !url.isFileURL {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .task(id: url) {
            guard let url, url.isFileURL else { return }
            image = await Task.detached(priority: .utility) { UIImage(contentsOfFile: url.path) }.value
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Theme.surfaceHi, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [fallbackTint.opacity(0.18), .clear], center: .center, startRadius: 2, endRadius: 90)
            Image(systemName: fallbackSymbol).font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(fallbackTint)
        }
    }

    /// Picks an icon + tint for a case from its metadata, for use both as this thumbnail's
    /// placeholder and as the loading-ring glyph. Bundled demo cases (Sun, Circuit board)
    /// have no CT-scan region, so they get a subject-appropriate icon instead of a generic one.
    static func fallback(for info: CaseInfo) -> (symbol: String, tint: Color) {
        let region = (info.metadata["region"] ?? "").lowercased()
        let name = (info.metadata["name"] ?? "").lowercased()
        let id = info.id.lowercased()
        if region.contains("sun") || region.contains("star") || name.contains("sun") || id.contains("sun") {
            return ("sun.max.fill", Color(red: 1.0, green: 0.7, blue: 0.25))
        }
        if region.contains("circuit") || name.contains("circuit") || id.contains("circuit") {
            return ("cpu", Theme.accent)
        }
        if region.contains("head") || id.hasPrefix("cq500") {
            return ("brain.head.profile", Theme.volumeColor)
        }
        return ("lungs.fill", Theme.textTertiary)
    }
}
