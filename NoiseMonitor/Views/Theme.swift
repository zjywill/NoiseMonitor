import SwiftUI
import UIKit

/// 「贴纸风」皮肤，从 Kite-iOS 的 GameTheme 精简移植过来：
/// 近白底、纯白大圆角卡片、带白边的彩色贴纸图标和按钮。
///
/// 强调色是填充色：压白字的只用 primary / green / coral；yellow 太亮，上面压 ink。
/// 中性色是动态的，深色模式下整套翻过来。
enum Theme {
    // MARK: 强调色

    static let primary = fixed(0x1E7BEF)
    static let green = fixed(0x16A34A)
    static let mint = fixed(0x1DBF6A)
    static let coral = fixed(0xEF4E57)
    static let yellow = fixed(0xFFC53D)
    static let orange = fixed(0xFF9F43)
    static let sky = fixed(0x38B6FF)
    static let lavender = fixed(0xA99CF5)
    static let slate = fixed(0x9AA3AF)

    // MARK: 中性色

    static let room = dynamic(light: 0xF5F7FB, dark: 0x111418)
    static let panel = dynamic(light: 0xFFFFFF, dark: 0x1C2027)
    static let hairline = dynamic(light: 0xE8ECF2, dark: 0x0B0D10)
    static let inset = dynamic(light: 0xF5F7FB, dark: 0x262B34)
    static let track = dynamic(light: 0xE8ECF2, dark: 0x363C47)
    static let ink = dynamic(light: 0x1F2430, dark: 0xF2F4F7)
    static let inkSecondary = dynamic(light: 0x5F6673, dark: 0xA3ABB7)
    static let disabledFill = dynamic(light: 0xC5CCD6, dark: 0x4A515D)
    /// 贴纸外圈的「白边」，深色下换成比卡片亮一档的灰
    static let rim = dynamic(light: 0xFFFFFF, dark: 0x2E3440)

    // MARK: 字体

    static func font(_ style: Font.TextStyle, _ weight: Font.Weight = .bold) -> Font {
        .system(style, design: .rounded).weight(weight)
    }

    /// 大读数用的固定字号
    static func number(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .rounded)
    }

    static let cornerRadius: CGFloat = 22

    private static func fixed(_ hex: UInt32) -> Color {
        Color(uiColor: rgb(hex))
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) })
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - 卡片

extension View {
    func panel(cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(Theme.panel)
            .clipShape(shape)
            .background(shape.fill(Theme.hairline).offset(y: 1))
            .shadow(color: .black.opacity(0.07), radius: 14, y: 10)
    }

    /// 卡片里嵌的小块
    func insetBlock(cornerRadius: CGFloat = 14) -> some View {
        background(Theme.inset, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// 贴纸的白边 + 柔和投影
    func sticker<S: InsettableShape>(_ shape: S, rim: CGFloat = 3) -> some View {
        background(shape.inset(by: -rim).fill(Theme.rim))
            .compositingGroup()
            .shadow(color: .black.opacity(0.14), radius: 6, y: 4)
    }
}

/// 标题行（彩色贴纸图标 + 粗圆体标题）+ 内容的一整张卡
struct StickerCard<Accessory: View, Content: View>: View {
    let title: String
    let systemImage: String
    let color: Color
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(systemName: systemImage, color: color, size: 32, cornerRadius: 11)
                Text(title)
                    .font(Theme.font(.headline, .heavy))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                accessory()
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }
}

extension StickerCard where Accessory == EmptyView {
    init(title: String, systemImage: String, color: Color, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, systemImage: systemImage, color: color, accessory: { EmptyView() }, content: content)
    }
}

// MARK: - 图标、按钮、胶囊

/// 彩色贴纸图标。cornerRadius 为 nil 时是圆的。
struct IconBadge: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 28
    var cornerRadius: CGFloat?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius ?? size / 2, style: .continuous)
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: shape)
            .background(shape.inset(by: -max(2, size * 0.08)).fill(Theme.rim))
            .compositingGroup()
            .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
            .accessibilityHidden(true)
    }
}

/// 贴纸按钮：纯色填充、一圈白边、按下去轻轻缩一下
struct StickerButtonStyle: ButtonStyle {
    var color: Color
    var foreground: Color = .white
    var cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        StickerBody(configuration: configuration, color: color, foreground: foreground, cornerRadius: cornerRadius)
    }

    private struct StickerBody: View {
        let configuration: Configuration
        let color: Color
        let foreground: Color
        let cornerRadius: CGFloat
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            configuration.label
                .font(Theme.font(.subheadline, .heavy))
                .foregroundStyle(isEnabled ? foreground : .white)
                .background(isEnabled ? color : Theme.disabledFill, in: shape)
                .sticker(shape)
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == StickerButtonStyle {
    static func sticker(_ color: Color, foreground: Color = .white, cornerRadius: CGFloat = 14) -> StickerButtonStyle {
        StickerButtonStyle(color: color, foreground: foreground, cornerRadius: cornerRadius)
    }
}

/// 不带任何按下效果的按钮样式，给自己画按下态的控件用
struct PlainPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// 状态胶囊
struct Pill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(Theme.font(.caption, .heavy))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 9)
        .frame(minHeight: 24)
        .background(Theme.inset, in: Capsule())
    }
}

/// 强度条：fraction 在 0…1，绿→黄→橙→红
struct LevelBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(LinearGradient(colors: [Theme.mint, Theme.yellow, Theme.orange, Theme.coral], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(geo.size.width * min(max(fraction, 0), 1), 10))
            }
        }
        .frame(height: 12)
        .animation(.easeOut(duration: 0.2), value: fraction)
        .accessibilityHidden(true)
    }
}

// MARK: - 顶栏

/// 替代系统导航栏的固定顶栏：左边大标题，右边放贴纸圆钮
struct TopBar<Trailing: View>: ViewModifier {
    let title: String
    let trailing: Trailing
    @Environment(\.tabBarInset) private var tabBarInset

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: tabBarInset).allowsHitTesting(false)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 12) {
                    Text(title)
                        .font(Theme.font(.largeTitle, .black))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    trailing
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 10)
                .background(Theme.room.opacity(0.94).ignoresSafeArea(edges: .top))
            }
            .background(Theme.room.ignoresSafeArea())
    }
}

extension View {
    func topBar<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        modifier(TopBar(title: title, trailing: trailing()))
    }
}

/// 顶栏右边的贴纸圆钮
struct RoundStickerButton: View {
    let systemImage: String
    let color: Color
    var foreground: Color = .white
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.heavy))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.sticker(color, foreground: foreground, cornerRadius: 22))
        .accessibilityLabel(label)
    }
}

// MARK: - 底部导航

/// 底部那条贴纸图标导航。系统 TabView 还在，只是藏了它自己的 tab bar。
struct StickerTabBar<Selection: Hashable>: View {
    struct Item: Identifiable {
        let value: Selection
        let title: String
        let systemImage: String
        let color: Color
        var id: Selection { value }
    }

    let items: [Item]
    @Binding var selection: Selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                button(item).frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .panel(cornerRadius: 28)
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    private func button(_ item: Item) -> some View {
        let isOn = item.value == selection
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button {
            selection = item.value
        } label: {
            VStack(spacing: 5) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(item.color, in: shape)
                    .sticker(shape)
                    // 选中那颗亮起来，歪一下再浮起来一点——贴纸被「拿起来」的感觉
                    .opacity(isOn ? 1 : 0.55)
                    .rotationEffect(.degrees(isOn && !reduceMotion ? -4 : 0))
                    .offset(y: isOn && !reduceMotion ? -3 : 0)
                    .animation(.snappy(duration: 0.25), value: isOn)
                Text(item.title)
                    .font(Theme.font(.caption, .heavy))
                    .foregroundStyle(isOn ? Theme.primary : Theme.inkSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressButtonStyle())
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }
}

extension EnvironmentValues {
    /// 底部贴纸导航条的高度，tab 页的滚动视图据此让位
    @Entry var tabBarInset: CGFloat = 0
}

extension Double {
    func formatted(decimals: Int) -> String {
        String(format: "%.\(decimals)f", self)
    }
}
