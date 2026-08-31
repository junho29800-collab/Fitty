import SwiftUI
import UIKit

/// Single source of truth for Fitty's light cream / ink / muted-gold look.
/// Buttons are boxy (corner radius 0–2 pt). No capsules, no continuous blobs.
enum FittyTheme {
    static let canvas = Color(red: 0.99, green: 0.96, blue: 0.88)
    static let ink = Color(red: 0.17, green: 0.15, blue: 0.11)
    static let accent = Color(red: 0.82, green: 0.68, blue: 0.22)
    /// HUD panel over AR passthrough — cream, not white-on-white.
    static let panel = Color(red: 0.99, green: 0.96, blue: 0.88).opacity(0.92)
    static let mutedInk = Color(red: 0.17, green: 0.15, blue: 0.11).opacity(0.62)

    static let corner: CGFloat = 2
    static let stroke: CGFloat = 2

    static let uiCanvas = UIColor(red: 0.99, green: 0.96, blue: 0.88, alpha: 1)
    static let uiInk = UIColor(red: 0.17, green: 0.15, blue: 0.11, alpha: 1)
    static let uiAccent = UIColor(red: 0.82, green: 0.68, blue: 0.22, alpha: 1)
}

enum FittyRoute: Hashable {
    case scan(rescanID: UUID?)
    case tryOn
    case wardrobe
    case settings
    case editor(UUID)
}

struct BoxyShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: FittyTheme.corner, style: .circular).path(in: rect)
    }
}

enum BoxyKind {
    case primary   // muted gold fill, ink stroke
    case secondary // cream fill, ink stroke
    case ghost     // cream fill, accent stroke
}

struct BoxyButtonStyle: ButtonStyle {
    var kind: BoxyKind = .secondary
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let fill: Color
        let stroke: Color
        let fg: Color
        switch kind {
        case .primary:
            fill = FittyTheme.accent
            stroke = FittyTheme.ink
            fg = FittyTheme.ink
        case .secondary:
            fill = FittyTheme.canvas
            stroke = FittyTheme.ink
            fg = FittyTheme.ink
        case .ghost:
            fill = FittyTheme.canvas.opacity(0.92)
            stroke = FittyTheme.accent
            fg = FittyTheme.ink
        }
        return configuration.label
            .font(.system(compact ? .subheadline : .body, design: .default).weight(.semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 8 : 12)
            .frame(maxWidth: .infinity)
            .background(fill)
            .clipShape(BoxyShape())
            .overlay(BoxyShape().stroke(stroke, lineWidth: FittyTheme.stroke))
            .opacity(configuration.isPressed ? 0.85 : 1) // S17 pressed state
    }
}

struct BoxyPanel<Content: View>: View {
    var opacity: Double = 0.92
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(14)
            .background(FittyTheme.canvas.opacity(opacity))
            .overlay(BoxyShape().stroke(FittyTheme.ink, lineWidth: FittyTheme.stroke))
            .clipShape(BoxyShape())
    }
}

/// Boxy L-shaped reticle ticks (not a rounded oval).
struct ReticleTicks: View {
    var length: CGFloat = 22
    var inset: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let r = geo.frame(in: .local).insetBy(dx: inset, dy: inset)
            Path { p in
                // TL
                p.move(to: CGPoint(x: r.minX, y: r.minY + length))
                p.addLine(to: CGPoint(x: r.minX, y: r.minY))
                p.addLine(to: CGPoint(x: r.minX + length, y: r.minY))
                // TR
                p.move(to: CGPoint(x: r.maxX - length, y: r.minY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.minY + length))
                // BL
                p.move(to: CGPoint(x: r.minX, y: r.maxY - length))
                p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
                p.addLine(to: CGPoint(x: r.minX + length, y: r.maxY))
                // BR
                p.move(to: CGPoint(x: r.maxX - length, y: r.maxY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - length))
            }
            .stroke(FittyTheme.accent, lineWidth: 2)
        }
        .allowsHitTesting(false)
    }
}
