import SwiftUI
import UIKit

/// The app's visual vocabulary in one place: the warm palette every screen
/// draws from, the rounded font ramp, and the handful of view modifiers that
/// give cards, screen backgrounds and error alerts the same shape everywhere.
/// Shared with the widget extension, so it stays free of app-only types.

// MARK: Colors

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// One color for light appearance, another for dark.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

/// Warm, quiet palette. Every event kind owns one color so the calendar,
/// timeline and buttons all read the same way.
enum MinaTheme {
    static let canvas = Color.adaptive(light: 0xFFF7F1, dark: 0x171413)
    static let card = Color.adaptive(light: 0xFFFFFF, dark: 0x231F1D)
    static let cardTint = Color.adaptive(light: 0xFDEDE3, dark: 0x2E2724)
    static let text = Color.adaptive(light: 0x2B2321, dark: 0xF4ECE6)
    static let textSecondary = Color.adaptive(light: 0x6E625D, dark: 0xB8ACA5)
    /// The quietest text still has to read: 4.6:1 on the canvas in light, 5.3:1 on a card in dark.
    static let textMuted = Color.adaptive(light: 0x7A706C, dark: 0x9C908A)
    static let border = Color.adaptive(light: 0xF1E3D9, dark: 0x3A332F)

    static let accent = Color(hex: 0xE4826F)
    static let bottle = Color(hex: 0xF0A04B)
    static let nursing = Color(hex: 0xE57C9B)
    static let diaper = Color(hex: 0x6FB56A)
    static let diaperDirty = Color(hex: 0xB78D62)
    static let sleep = Color(hex: 0x7C8FE0)
    static let note = Color(hex: 0x9A8FB8)
    static let warning = Color(hex: 0xE3A23C)
    static let danger = Color(hex: 0xD9534F)
}

// MARK: Type

extension Font {
    static func mina(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

// MARK: Modifiers

struct MinaCard: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(MinaTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(MinaTheme.border, lineWidth: 1))
    }
}

/// Keeps scroll content readable on an iPad: past `max` points the column
/// stops growing and sits centered, so cards never stretch across a 13-inch
/// screen. On a phone (compact width) it does nothing at all.
struct ReadableWidth: ViewModifier {
    var max: CGFloat
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content
                .padding(.horizontal, 8)
                .frame(maxWidth: max)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

extension View {
    func minaCard(padding: CGFloat = 16) -> some View { modifier(MinaCard(padding: padding)) }

    /// Centers content in a column no wider than `max` on regular-width
    /// screens (iPad). Apply to a scroll view's content, or to a `Form`.
    func readableWidth(_ max: CGFloat = 680) -> some View { modifier(ReadableWidth(max: max)) }

    /// A sheet that presents as a centered form on iPad (iOS 18+) instead of
    /// a full-height page sheet; unchanged on iPhone and on iOS 17.
    @ViewBuilder
    func minaSheet() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(.form)
        } else {
            self
        }
    }

    /// The warm page background every full screen and sheet sits on.
    func minaCanvas() -> some View { background(MinaTheme.canvas.ignoresSafeArea()) }

    /// Shows `message` in a one-button alert and clears it on dismiss. Every
    /// screen keeps its failure in an optional `String`, so this is the whole
    /// error path: `.errorAlert($error)`.
    func errorAlert(_ message: Binding<String?>, title: String = "Couldn't save") -> some View {
        alert(title, isPresented: Binding(get: { message.wrappedValue != nil },
                                          set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK") {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
