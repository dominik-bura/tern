import AppKit
import CoreText
import SwiftUI

/// A System Settings–style sidebar icon: a white symbol on a colored rounded square.
struct SidebarIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The icon for a destination: a Dia profile avatar, the browser's app icon, or a question mark.
struct DestinationIcon: View {
    @EnvironmentObject private var model: AppModel
    let destination: BrowserDestination
    var size: CGFloat = 18

    var body: some View {
        Group {
            switch destination {
            case .ask:
                Image(systemName: "questionmark.circle.fill")
                    .resizable().scaledToFit().foregroundStyle(.secondary)
                    .padding(size * 0.06)
            case .browser(let id):
                if let browser = model.browsers.first(where: { $0.id == id }) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: browser.url.path)).resizable()
                } else {
                    Image(systemName: "exclamationmark.triangle.fill").resizable().scaledToFit()
                        .foregroundStyle(.yellow).padding(size * 0.1)
                }
            case .dia(let profile):
                if let item = model.profileItem(for: destination) { ProfileBadge(item: item, size: size) }
                else { ProfileAvatar(name: profile.name, size: size) }
            case .profile(let profile):
                if let item = model.profileItem(for: destination) { ProfileBadge(item: item, size: size) }
                else { ProfileAvatar(name: profile.name, size: size) }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A profile's picture, or its initial on the profile's color as stored by the browser.
struct ProfileBadge: View {
    let item: ProfileItem
    var size: CGFloat = 18

    var body: some View {
        if let url = item.pictureURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFill()
                .frame(width: size, height: size).clipShape(Circle())
        } else {
            ProfileAvatar(name: item.name, size: size, color: item.color.map { Color(nsColor: NSColor(rgb: $0)) })
        }
    }
}

/// A colored initial; without a stored color, one is derived from the name so profiles stay distinct.
struct ProfileAvatar: View {
    let name: String
    var size: CGFloat = 18
    var color: Color?

    private static let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .red]

    private var fill: Color {
        if let color { return color }
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Self.palette[sum % Self.palette.count]
    }

    private var initial: String { name.first.map { String($0).uppercased() } ?? "?" }

    var body: some View {
        let line = Self.line(for: initial, size: size * 0.52)
        Canvas { context, canvasSize in
            // Center the glyph's ink, not its line box, so the letter sits optically centered.
            let ink = CTLineGetImageBounds(line, nil)
            context.withCGContext { cg in
                cg.textMatrix = .identity
                cg.translateBy(x: 0, y: canvasSize.height)
                cg.scaleBy(x: 1, y: -1)
                cg.textPosition = CGPoint(x: (canvasSize.width - ink.width) / 2 - ink.minX,
                                          y: (canvasSize.height - ink.height) / 2 - ink.minY)
                CTLineDraw(line, cg)
            }
        }
        .frame(width: size, height: size)
        .background(fill.gradient, in: Circle())
        .accessibilityLabel(name)
    }

    private static func line(for string: String, size: CGFloat) -> CTLine {
        let base = NSFont.systemFont(ofSize: size, weight: .semibold)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        let text = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: NSColor.white])
        return CTLineCreateWithAttributedString(text)
    }
}

/// Picker for a routing destination, grouped into Dia profiles and browsers.
struct DestinationPicker: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    @Binding var selection: BrowserDestination

    var body: some View {
        Picker(title, selection: $selection) {
            Text("Ask Every Time").tag(BrowserDestination.ask)
            if case .dia(let profile) = selection, !model.profiles.contains(profile) {
                Text("\(profile.name) (profile not found)").tag(selection)
            }
            if case .profile(let profile) = selection, model.profileItem(for: selection) == nil {
                Text("\(profile.name) (profile not found)").tag(selection)
            }
            if case .browser(let id) = selection, !model.browsers.contains(where: { $0.id == id }) {
                Text("Missing Browser (\(id))").tag(selection)
            }
            Section("Browsers") {
                ForEach(model.browsers) { Text($0.name).tag(BrowserDestination.browser($0.id)) }
            }
            ForEach(model.browsers.filter { !model.profileItems(of: $0).isEmpty }) { browser in
                Section("\(browser.name) Profiles") {
                    ForEach(model.profileItems(of: browser)) { Text($0.name).tag($0.destination) }
                }
            }
        }
        .pickerStyle(.menu)
    }
}

/// Secondary explanatory text below a form section.
struct SectionFooter: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote).foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Settings window metrics and colors (matched to the reference design)

enum SettingsStyle {
    static let sidebar = dynamic(dark: (28, 27, 25), light: (236, 236, 235))
    static let content = dynamic(dark: (22, 21, 20), light: (245, 245, 244))
    static let card = dynamic(dark: (27, 27, 26), light: (255, 255, 255))
    static let separator = dynamic(dark: (38, 38, 37), light: (230, 230, 229))
    static let sidebarDivider = dynamic(dark: (51, 50, 48), light: (218, 218, 217))
    static let selection = dynamic(dark: (40, 39, 37), light: (222, 222, 221))
    static let searchFill = dynamic(dark: (58, 57, 55), light: (226, 226, 225))
    static let searchStroke = dynamic(dark: (68, 65, 63), light: (214, 214, 213))

    static let sidebarWidth: CGFloat = 231
    static let contentMargin: CGFloat = 16
    static let rowInset: CGFloat = 12
    static let rowHeight: CGFloat = 47
    static let cardRadius: CGFloat = 10

    private static func dynamic(dark: (CGFloat, CGFloat, CGFloat), light: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: 1)
        })
    }
}

/// A section of the settings page: an optional header above a rounded card of rows.
struct SettingsSection<Content: View, Accessory: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Spacer()
                    accessory
                }
                .padding(.horizontal, SettingsStyle.rowInset)
                .frame(height: 36, alignment: .center)
            }
            VStack(spacing: 0) { content }
                .background(SettingsStyle.card, in: RoundedRectangle(cornerRadius: SettingsStyle.cardRadius, style: .continuous))
            if let footer {
                Text(footer).font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, SettingsStyle.rowInset).padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension SettingsSection where Accessory == EmptyView {
    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, footer: footer, content: content, accessory: { EmptyView() })
    }
}

/// A row with a title, optional subtitle, and trailing controls.
struct SettingsRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var dimmed = false
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .opacity(dimmed ? 0.5 : 1)
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, SettingsStyle.rowInset)
        .padding(.vertical, 10)
        .frame(minHeight: subtitle == nil ? SettingsStyle.rowHeight : 57)
        .contentShape(Rectangle())
    }
}

extension SettingsRow where Leading == EmptyView {
    init(_ title: String, subtitle: String? = nil, dimmed: Bool = false, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle, dimmed: dimmed, leading: { EmptyView() }, trailing: trailing)
    }
}

/// Separator between rows inside a card, inset like the row content.
struct RowSeparator: View {
    var body: some View {
        Rectangle().fill(SettingsStyle.separator).frame(height: 1)
            .padding(.horizontal, SettingsStyle.rowInset).accessibilityHidden(true)
    }
}

/// Scrolling page container for a settings section.
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(.horizontal, SettingsStyle.contentMargin)
                .padding(.top, 14).padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension View {
    /// Liquid Glass buttons (with hover and press feedback) on macOS 26+, bordered buttons before.
    @ViewBuilder func nativeButtonStyle() -> some View {
        if #available(macOS 26.0, *) { buttonStyle(.glass) } else { buttonStyle(.bordered) }
    }

    @ViewBuilder func nativeProminentButtonStyle() -> some View {
        if #available(macOS 26.0, *) { buttonStyle(.glassProminent) } else { buttonStyle(.borderedProminent) }
    }
}
