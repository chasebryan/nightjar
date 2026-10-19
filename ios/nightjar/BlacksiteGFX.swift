import Foundation
import UIKit
import SwiftUI
import JavaScriptCore

/// BLACKSITE GFX — the console's graphics
/// engine (the operator's order, 2026-10-19:
/// "generating its own graphics through its
/// graphics engine").
///
/// Two hands. The canvas hand is a vector
/// drawing surface — background, rectangles,
/// circles, lines, text — that JS programs
/// drive through the gfx object and the
/// shell drives through the gfx command.
/// The pixel hand computes pictures per
/// pixel in Swift: a mandelbrot, a plasma,
/// a starfield. Both render to real images;
/// gfx show files the picture as a PNG in
/// the console's own file system and puts
/// the picture itself in the terminal, so
/// the console's output is not only words.
final class BlacksiteGFX {
    static let shared = BlacksiteGFX()

    /// Set by the shell: a shown picture
    /// lands in the transcript. Called on
    /// the main queue with (image, path).
    var onShow: ((UIImage, String) -> Void)?

    private var canvasSize = CGSize(
        width: 640, height: 640)
    private var canvasBG = "black"
    private var ops: [(CGContext) -> Void] = []
    private var lastImage: UIImage?

    // MARK: Colors

    static func color(_ spec: String) -> UIColor {
        let key = spec.lowercased()
        switch key {
        case "accent":
            return UIColor(
                ThemeCenter.shared.current.accent)
        case "glow":
            return UIColor(
                ThemeCenter.shared.current.glow)
        case "black": return .black
        case "white": return .white
        case "orange": return .systemOrange
        case "red": return .systemRed
        case "green": return .systemGreen
        case "blue": return .systemBlue
        case "purple": return .systemPurple
        case "pink": return .systemPink
        case "yellow": return .systemYellow
        case "teal": return .systemTeal
        case "gray", "grey": return .systemGray
        case "dark":
            return UIColor(white: 0.06, alpha: 1)
        default:
            break
        }
        var hex = key
        if hex.hasPrefix("#") {
            hex = String(hex.dropFirst())
        }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }
                .joined()
        }
        guard hex.count == 6,
              let value = UInt32(hex, radix: 16)
        else { return .white }
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF)
                / 255,
            green: CGFloat((value >> 8) & 0xFF)
                / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1)
    }

    // MARK: The canvas hand

    func begin(width: Double, height: Double) {
        canvasSize = CGSize(
            width: max(16, min(2048, width)),
            height: max(16, min(2048, height)))
        ops = []
        canvasBG = "black"
        lastImage = nil
    }

    func background(_ spec: String) {
        canvasBG = spec
    }

    func rect(x: Double, y: Double, w: Double,
              h: Double, color spec: String) {
        let fill = Self.color(spec)
        ops.append { ctx in
            ctx.setFillColor(fill.cgColor)
            ctx.fill(CGRect(x: x, y: y,
                            width: w, height: h))
        }
    }

    func circle(cx: Double, cy: Double,
                r: Double, color spec: String) {
        let fill = Self.color(spec)
        ops.append { ctx in
            ctx.setFillColor(fill.cgColor)
            ctx.fillEllipse(in: CGRect(
                x: cx - r, y: cy - r,
                width: r * 2, height: r * 2))
        }
    }

    func ring(cx: Double, cy: Double, r: Double,
              width: Double, color spec: String) {
        let stroke = Self.color(spec)
        ops.append { ctx in
            ctx.setStrokeColor(stroke.cgColor)
            ctx.setLineWidth(width)
            ctx.strokeEllipse(in: CGRect(
                x: cx - r, y: cy - r,
                width: r * 2, height: r * 2))
        }
    }

    func line(x1: Double, y1: Double,
              x2: Double, y2: Double,
              color spec: String, width: Double) {
        let stroke = Self.color(spec)
        ops.append { ctx in
            ctx.setStrokeColor(stroke.cgColor)
            ctx.setLineWidth(max(1, width))
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x1, y: y1))
            ctx.addLine(to: CGPoint(x: x2, y: y2))
            ctx.strokePath()
        }
    }

    func text(_ string: String, x: Double,
              y: Double, size: Double,
              color spec: String) {
        let fill = Self.color(spec)
        let font = UIFont.monospacedSystemFont(
            ofSize: max(6, size),
            weight: .semibold)
        ops.append { _ in
            (string as NSString).draw(
                at: CGPoint(x: x, y: y),
                withAttributes: [
                    .font: font,
                    .foregroundColor: fill,
                ])
        }
    }

    func renderCanvas() -> UIImage {
        let renderer = UIGraphicsImageRenderer(
            size: canvasSize)
        let image = renderer.image { rendererCtx in
            let ctx = rendererCtx.cgContext
            ctx.setFillColor(
                Self.color(canvasBG).cgColor)
            ctx.fill(CGRect(origin: .zero,
                            size: canvasSize))
            for op in ops { op(ctx) }
        }
        lastImage = image
        return image
    }

    // MARK: The pixel hand

    private struct LCG {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005
                &+ 1442695040888963407
            return Double(
                (state >> 11) & 0x1FFFFF)
                / Double(0x200000)
        }
    }

    private func pixelImage(
        width: Int, height: Int,
        shade: (Int, Int) -> (UInt8, UInt8, UInt8)
    ) -> UIImage? {
        let w = max(16, min(1600, width))
        let h = max(16, min(1600, height))
        var buffer = [UInt8](
            repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let (r, g, b) = shade(x, y)
                let i = (y * w + x) * 4
                buffer[i] = r
                buffer[i + 1] = g
                buffer[i + 2] = b
                buffer[i + 3] = 255
            }
        }
        return buffer.withUnsafeMutableBytes {
            raw -> UIImage? in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(
                    data: base, width: w,
                    height: h,
                    bitsPerComponent: 8,
                    bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo
                        .premultipliedLast.rawValue),
                  let cg = ctx.makeImage()
            else { return nil }
            return UIImage(cgImage: cg)
        }
    }

    func mandelbrot(width: Int, height: Int)
        -> UIImage? {
        let image = pixelImage(
            width: width, height: height
        ) { x, y in
            let re = (Double(x) / Double(width))
                * 3.2 - 2.2
            let im = (Double(y) / Double(height))
                * 3.2 - 1.6
            var zr = 0.0
            var zi = 0.0
            var steps = 0
            let maxSteps = 90
            while zr * zr + zi * zi < 4,
                  steps < maxSteps {
                let next = zr * zr - zi * zi + re
                zi = 2 * zr * zi + im
                zr = next
                steps += 1
            }
            if steps >= maxSteps {
                return (4, 4, 8)
            }
            let t = Double(steps)
                / Double(maxSteps)
            let accent = ThemeCenter.shared
                .current.accent
            var ar: CGFloat = 0
            var ag: CGFloat = 0
            var ab: CGFloat = 0
            UIColor(accent).getRed(
                &ar, green: &ag, blue: &ab,
                alpha: nil)
            let glow = pow(t, 0.55)
            return (UInt8(glow * Double(ar) * 255),
                    UInt8(glow * Double(ag) * 255),
                    UInt8(min(1, glow * 0.5
                        + Double(ab) * glow * 0.6)
                        * 255))
        }
        if let image = image {
            lastImage = image
        }
        return image
    }

    func plasma(width: Int, height: Int,
                seed: Double) -> UIImage? {
        let image = pixelImage(
            width: width, height: height
        ) { x, y in
            let dx = Double(x) / 26.0
            let dy = Double(y) / 26.0
            var v = sin(dx + seed)
            v += sin(dy - seed * 0.7)
            v += sin((dx + dy) * 0.6 + seed * 1.3)
            v += sin(sqrt(dx * dx + dy * dy)
                     - seed)
            let t = (v + 4) / 8
            let r = UInt8(255 * abs(sin(
                t * Double.pi)))
            let g = UInt8(120 * abs(sin(
                t * Double.pi + 1.2)))
            let b = UInt8(255 * abs(cos(
                t * Double.pi * 0.8)))
            return (r, g, b)
        }
        if let image = image {
            lastImage = image
        }
        return image
    }

    func starfield(width: Int, height: Int,
                   seed: UInt64) -> UIImage? {
        var rng = LCG(state: seed == 0
                      ? 88172645463325252 : seed)
        let w = max(16, min(1600, width))
        let h = max(16, min(1600, height))
        // Star cores on a map, so a pixel
        // asks only its own neighbourhood —
        // wallpaper-sized fields stay fast.
        var cores: [Int: UInt8] = [:]
        for _ in 0..<420 {
            let sx = Int(rng.next() * Double(w))
            let sy = Int(rng.next() * Double(h))
            cores[sy * w + sx] =
                UInt8(90 + rng.next() * 165)
        }
        let image = pixelImage(
            width: width, height: height
        ) { x, y in
            var bright: UInt8 = 6
            for dy in -1...1 {
                for dx in -1...1 {
                    guard let v = cores[
                        (y + dy) * w + (x + dx)]
                    else { continue }
                    let cand = (dx == 0 && dy == 0)
                        ? v : v / 3
                    if cand > bright {
                        bright = cand
                    }
                }
            }
            return (bright, bright,
                    UInt8(min(255,
                              Int(bright) + 18)))
        }
        if let image = image {
            lastImage = image
        }
        return image
    }

    /// Render a named pixel picture. Returns
    /// the picture or nil for a bad name.
    func renderNamed(_ name: String,
                     width: Int, height: Int)
        -> UIImage? {
        switch name.lowercased() {
        case "mandelbrot", "fractal":
            return mandelbrot(width: width,
                              height: height)
        case "plasma":
            return plasma(width: width,
                          height: height,
                          seed: Double(
                            Int(Date()
                                .timeIntervalSince1970)
                            % 360))
        case "stars", "starfield":
            return starfield(
                width: width, height: height,
                seed: UInt64(Date()
                    .timeIntervalSince1970))
        default:
            return nil
        }
    }

    // MARK: Showing + filing

    /// File the current picture as a PNG in
    /// the console's file system and put it
    /// in the terminal. Returns the path.
    @discardableResult
    func show(path: String?) -> String {
        let image: UIImage
        if ops.isEmpty, let last = lastImage {
            image = last
        } else {
            image = renderCanvas()
        }
        let target = BlacksiteFS.normalize(
            path ?? "/tmp/canvas.png",
            cwd: BlacksiteFS.home)
        if let png = image.pngData() {
            BlacksiteFS.writeData(target,
                                  data: png)
        }
        let shown = image
        DispatchQueue.main.async { [weak self] in
            self?.onShow?(shown, target)
        }
        return target
    }

    /// The demo card: the house, drawn.
    func demo() -> UIImage {
        begin(width: 720, height: 460)
        background("dark")
        ring(cx: 360, cy: 210, r: 120,
             width: 5, color: "accent")
        ring(cx: 360, cy: 210, r: 88,
             width: 2, color: "glow")
        circle(cx: 360, cy: 210, r: 9,
               color: "accent")
        line(x1: 60, y1: 400, x2: 660, y2: 400,
             color: "accent", width: 2)
        text("BLACKSITE", x: 288, y: 356,
             size: 30, color: "white")
        text("graphics engine — first light",
             x: 196, y: 416, size: 17,
             color: "glow")
        return renderCanvas()
    }

    // MARK: The JavaScript bridge

    static func installBridge(into context: JSContext,
                              owner: BlacksiteJS) {
        let gfx = BlacksiteGFX.shared
        let begin: @convention(block)
            (Double, Double) -> Void = { w, h in
            gfx.begin(width: w, height: h)
        }
        context.setObject(
            begin,
            forKeyedSubscript: "__gfxBegin"
                as NSString)
        let bg: @convention(block)
            (String) -> Void = { spec in
            gfx.background(spec)
        }
        context.setObject(
            bg,
            forKeyedSubscript: "__gfxBG" as NSString)
        let rect: @convention(block)
            (Double, Double, Double, Double,
             String) -> Void = { x, y, w, h, c in
            gfx.rect(x: x, y: y, w: w, h: h,
                     color: c)
        }
        context.setObject(
            rect,
            forKeyedSubscript: "__gfxRect"
                as NSString)
        let circle: @convention(block)
            (Double, Double, Double,
             String) -> Void = { cx, cy, r, c in
            gfx.circle(cx: cx, cy: cy, r: r,
                       color: c)
        }
        context.setObject(
            circle,
            forKeyedSubscript: "__gfxCircle"
                as NSString)
        let line: @convention(block)
            (Double, Double, Double, Double,
             String, Double) -> Void = {
                x1, y1, x2, y2, c, w in
            gfx.line(x1: x1, y1: y1, x2: x2,
                     y2: y2, color: c, width: w)
        }
        context.setObject(
            line,
            forKeyedSubscript: "__gfxLine"
                as NSString)
        let text: @convention(block)
            (String, Double, Double, Double,
             String) -> Void = { s, x, y, size, c in
            gfx.text(s, x: x, y: y, size: size,
                     color: c)
        }
        context.setObject(
            text,
            forKeyedSubscript: "__gfxText"
                as NSString)
        let render: @convention(block)
            (String, Double, Double) -> Bool = {
                name, w, h in
            gfx.renderNamed(name,
                            width: Int(w),
                            height: Int(h)) != nil
        }
        context.setObject(
            render,
            forKeyedSubscript: "__gfxRender"
                as NSString)
        let show: @convention(block)
            (String) -> String = { path in
            gfx.show(path: path.isEmpty
                     ? nil : path)
        }
        context.setObject(
            show,
            forKeyedSubscript: "__gfxShow"
                as NSString)
        context.evaluateScript("""
var gfx = {
    begin: function(w, h) {
        __gfxBegin(w || 640, h || 640); },
    bg: function(c) { __gfxBG(c); },
    rect: function(x, y, w, h, c) {
        __gfxRect(x, y, w, h, c || "white"); },
    circle: function(x, y, r, c) {
        __gfxCircle(x, y, r, c || "white"); },
    line: function(x1, y1, x2, y2, c, w) {
        __gfxLine(x1, y1, x2, y2,
                  c || "white", w || 2); },
    text: function(s, x, y, size, c) {
        __gfxText(String(s), x, y,
                  size || 20, c || "white"); },
    render: function(name, w, h) {
        return __gfxRender(name, w || 640,
                           h || 640); },
    show: function(path) {
        return __gfxShow(path || ""); }
};
""")
    }
}

/// BLACKSITE WALLPAPER — the room's own
/// wallpaper (Chase's order, 2026-10-19:
/// "give it its own wallpaper").
///
/// The console's graphics engine paints it:
/// a starfield by default, plasma or a
/// mandelbrot on request. The kind is kept
/// in the console's own papers
/// (/etc/wallpaper-kind) and the picture
/// itself in its tree (/var/wallpaper-<kind
/// >.png), so the room's wallpaper is a
/// file the operator owns — 'view
/// /var/wallpaper-stars.png' shows it, the
/// console's 'wallpaper' command changes
/// it. Rendered once per kind, off the
/// main thread, at portrait size.
final class BlacksiteWallpaper:
    ObservableObject {
    static let shared = BlacksiteWallpaper()

    @Published private(set) var image: UIImage?
    private var generating = false

    static let kinds = ["stars", "plasma",
                        "mandelbrot"]

    var kind: String {
        let stored = BlacksiteFS.readText(
            "/etc/wallpaper-kind")?
            .trimmingCharacters(
                in: .whitespacesAndNewlines)
            .lowercased()
        return Self.kinds.contains(stored ?? "")
            ? (stored ?? "stars") : "stars"
    }

    private func file(for kind: String)
        -> String {
        "/var/wallpaper-" + kind + ".png"
    }

    /// Paint if there is nothing hanging:
    /// the filed copy first (it survives
    /// relaunch), a fresh render behind it.
    func ensure() {
        guard image == nil, !generating else {
            return
        }
        let current = kind
        if let data = BlacksiteFS.readData(
            file(for: current)),
           let filed = UIImage(data: data) {
            image = filed
            return
        }
        regenerate(kind: current)
    }

    func regenerate(kind newKind: String) {
        let valid = Self.kinds.contains(newKind)
            ? newKind : "stars"
        BlacksiteFS.writeText(
            "/etc/wallpaper-kind", text: valid)
        guard !generating else { return }
        generating = true
        DispatchQueue.global(
            qos: .userInitiated).async {
            [weak self] in
            let picture = BlacksiteGFX.shared
                .renderNamed(valid, width: 620,
                             height: 1340)
            if let picture = picture,
               let png = picture.pngData() {
                BlacksiteFS.writeData(
                    "/var/wallpaper-" + valid
                    + ".png", data: png)
            }
            DispatchQueue.main.async {
                guard let self = self
                else { return }
                self.generating = false
                if self.kind == valid {
                    self.image = picture
                }
            }
        }
    }
}

/// The wallpaper as a backdrop: full-bleed,
/// generated art, with a plain dark fall
/// while the engine is still painting.
struct BlacksiteWallpaperView: View {
    @ObservedObject private var wallpaper =
        BlacksiteWallpaper.shared
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Group {
            if let image = wallpaper.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width,
                           height: height)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [Color(white: 0.05),
                             Color.black],
                    startPoint: .top,
                    endPoint: .bottom)
                    .frame(width: width,
                           height: height)
            }
        }
        .onAppear { wallpaper.ensure() }
    }
}
