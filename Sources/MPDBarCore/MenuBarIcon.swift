import AppKit

/// Menu bar icon: the SF Symbol `radio` with a small badge for the playback state, drawn once per
/// state into a template image, so macOS tints it for light and dark menu bars.
///
///     stopped  radio alone
///     playing  radio + play badge
///     paused   radio + pause badge
///     muted    radio + slash badge (playing or paused while the server is muted)
@MainActor
public enum MenuBarIcon {
    public enum Badge: String, CaseIterable, Sendable {
        case none, play, pause, mute
    }

    public static func badge(state: PlaybackState, muted: Bool) -> Badge {
        switch state {
        case .stopped: return .none
        case .playing: return muted ? .mute : .play
        case .paused: return muted ? .mute : .pause
        }
    }

    /// Canvas in points; the bitmap is drawn at 3x so it stays sharp when scaled up in the panel.
    static let size = NSSize(width: 22, height: 18)
    static let scale: CGFloat = 3

    private static var cache: [Badge: NSImage] = [:]

    public static func image(_ badge: Badge) -> NSImage {
        if let cached = cache[badge] { return cached }
        let made = render(badge)
        cache[badge] = made
        return made
    }

    /// PNG of the icon (black on transparent), used by `mpdbar-probe render-icons` and CI.
    public static func png(_ badge: Badge) -> Data? {
        guard let rep = image(badge).representations.first as? NSBitmapImageRep else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func render(_ badge: Badge) -> NSImage {
        let fallback = NSImage(systemSymbolName: "radio", accessibilityDescription: "MPD Bar") ?? NSImage()
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return fallback }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        let cg = ctx.cgContext
        cg.scaleBy(x: scale, y: scale)

        // Base symbol. Template images keep only the alpha channel, so colors do not matter.
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        if let symbol = NSImage(systemSymbolName: "radio", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let s = symbol.size
            symbol.draw(in: NSRect(x: 0, y: (size.height - s.height) / 2 + 1, width: s.width, height: s.height))
        }

        if badge != .none {
            let c = CGPoint(x: size.width - 5, y: 5)
            // Gap around the badge, so it reads as a separate mark.
            cg.setBlendMode(.clear)
            cg.fillEllipse(in: CGRect(x: c.x - 6.2, y: c.y - 6.2, width: 12.4, height: 12.4))
            cg.setBlendMode(.normal)
            cg.setFillColor(NSColor.black.cgColor)
            cg.fillEllipse(in: CGRect(x: c.x - 4.8, y: c.y - 4.8, width: 9.6, height: 9.6))
            // The glyph is cut out of the badge.
            cg.setBlendMode(.clear)
            switch badge {
            case .play:
                let p = CGMutablePath()
                p.move(to: CGPoint(x: c.x - 1.6, y: c.y - 2.5))
                p.addLine(to: CGPoint(x: c.x + 2.7, y: c.y))
                p.addLine(to: CGPoint(x: c.x - 1.6, y: c.y + 2.5))
                p.closeSubpath()
                cg.addPath(p)
                cg.fillPath()
            case .pause:
                cg.fill(CGRect(x: c.x - 2.2, y: c.y - 2.4, width: 1.5, height: 4.8))
                cg.fill(CGRect(x: c.x + 0.7, y: c.y - 2.4, width: 1.5, height: 4.8))
            case .mute:
                cg.setLineWidth(1.5)
                cg.setLineCap(.round)
                cg.move(to: CGPoint(x: c.x - 2.4, y: c.y + 2.4))
                cg.addLine(to: CGPoint(x: c.x + 2.4, y: c.y - 2.4))
                cg.strokePath()
            case .none:
                break
            }
            cg.setBlendMode(.normal)
        }

        NSGraphicsContext.restoreGraphicsState()
        rep.size = size
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }
}
