import SwiftUI
import UsageCore

/// The menu bar item. `MenuBarExtra` labels ignore most modifiers (colors, monospaced digits),
/// so the label is drawn into an image: a template image normally, so macOS adapts it to the
/// menu bar, or a colored one when a limit is near and coloring is on.
struct MenuBarLabel: View {
    let store: UsageStore
    let settings: AppSettings

    var body: some View {
        let summary = MenuBarSummary(
            statuses: store.statuses,
            enabled: store.shownProviders,
            mode: settings.displayMode,
            pinnedMetricID: settings.pinnedMetricID
        )
        Image(nsImage: MenuBarImage.render(summary, colorize: settings.colorizeMenuBar))
            .accessibilityLabel(MenuBarImage.accessibilityText(summary))
    }
}

/// "▮ 46%" for one value, or "✳︎ 46%  ⬡ 62%  ⦿ $45" (each service's logo) in per-service mode.
struct MenuBarLabelContent: View {
    let summary: MenuBarSummary
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            if summary.segments.first?.provider == nil {
                UsageBar(fill: summary.fill)
            }
            ForEach(Array(summary.segments.enumerated()), id: \.offset) { index, segment in
                HStack(spacing: 3) {
                    if let provider = segment.provider {
                        provider.logo
                            .resizable()
                            .scaledToFit()
                            .frame(width: 13, height: 13)
                    }
                    Text(Format.compact(segment.metric))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                }
                .padding(.leading, index > 0 ? 3 : 0)
            }
        }
        .foregroundStyle(color)
        .fixedSize()
        .padding(.vertical, 2)
    }
}

/// A vertical bar that fills from the bottom, like a battery level turned upright.
/// The empty part is drawn translucent, so it still reads as a template image.
struct UsageBar: View {
    let fill: Double

    static let size = CGSize(width: 7, height: 15)

    var body: some View {
        let height = Self.size.height
        // Anything above zero stays visible, even 1%.
        let filled = fill > 0 ? max(height * fill, 2) : 0
        ZStack(alignment: .bottom) {
            Rectangle().opacity(0.3)
            Rectangle().frame(height: filled)
        }
        .frame(width: Self.size.width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
    }
}

enum MenuBarImage {
    static func render(_ summary: MenuBarSummary, colorize: Bool) -> NSImage {
        let tint = colorize ? summary.level.tint : nil
        let renderer = ImageRenderer(content: MenuBarLabelContent(summary: summary, color: tint ?? .black))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage
            ?? NSImage(systemSymbolName: "powermeter", accessibilityDescription: nil)
            ?? NSImage()
        image.isTemplate = tint == nil
        return image
    }

    static func accessibilityText(_ summary: MenuBarSummary) -> String {
        guard !summary.segments.isEmpty else { return String(localized: "Usage AI") }
        let parts = summary.segments.map { segment in
            let name = segment.provider?.displayName ?? segment.metric.role.title
            return "\(name) \(Format.compact(segment.metric))"
        }
        return String(localized: "Usage AI: \(parts.joined(separator: ", "))")
    }
}

extension ProviderID {
    /// The service's monochrome logo, a template image that takes the foreground color.
    var logo: Image {
        switch self {
        case .claude: Image("logo-claude")
        case .cursor: Image("logo-cursor")
        case .openAI: Image("logo-openai")
        }
    }
}

/// The logo next to a service's name, sized to sit with headline text.
struct ProviderLogo: View {
    let provider: ProviderID
    var size: CGFloat = 15

    var body: some View {
        provider.logo
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension UsageLevel {
    /// `nil` for normal, so callers fall back to the accent or template color.
    var tint: Color? {
        switch self {
        case .normal: nil
        case .warning: .orange
        case .critical: .red
        }
    }
}
