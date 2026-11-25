import UIKit

/// The demo library's pictures (`PSNDemo`'s `demo://` addresses), drawn here: each invented game
/// gets a scene of its own (a sky, a light, layers of land, specks in the air), its title as a
/// logo, an icon, and trophy badges in its colours. Nothing comes from a real game or a store.
/// `ScreenshotDemo` hands them to `RemotePhoto` through `DesignKitPhotoLoader`.
enum DemoArt {
    /// `demo://art/<slug>/hub|icon|logo|dlc`, `demo://trophy/<slug>/<id>`, `demo://art/avatar`.
    static func image(for url: URL) -> UIImage? {
        if let image = cache.image(url.absoluteString) { return image }
        guard url.scheme == "demo", let image = draw(url) else { return nil }
        cache.keep(image, for: url.absoluteString)
        return image
    }

    private static let cache = ImageCache()

    private static func draw(_ url: URL) -> UIImage? {
        let parts = url.path.split(separator: "/").map(String.init)
        switch url.host() ?? "" {
        case "art" where parts == ["avatar"]:
            return avatar()
        case "art" where parts.count == 2:
            let theme = Theme.named(parts[0])
            switch parts[1] {
            case "hub": return render(CGSize(width: 1920, height: 1080), opaque: true) { scene(theme, $0, $1) }
            case "icon": return icon(theme, dlc: false)
            case "dlc": return icon(theme, dlc: true)
            case "logo": return logo(theme)
            default: return nil
            }
        case "trophy" where parts.count == 2:
            return trophy(Theme.named(parts[0]), id: Int(parts[1]) ?? 0)
        default:
            return nil
        }
    }

    // MARK: Themes

    enum Motif: Sendable {
        case castle, planet, synth, grove, fog, lanterns, ridge, islands
    }

    struct Theme: @unchecked Sendable {
        let name: String
        let sky: [UIColor]
        let light: UIColor
        let land: [UIColor]
        let specks: UIColor
        let motif: Motif
        let font: String
        let symbols: [String]

        static func named(_ slug: String) -> Theme {
            all[slug] ?? all["emberfall"]!
        }

        static let all: [String: Theme] = [
            "emberfall": Theme(
                name: "Emberfall: The Last Crown",
                sky: [rgb(0x1B0B1F), rgb(0x5A1426), rgb(0xD2461E)], light: rgb(0xFFB347),
                land: [rgb(0x3A1020), rgb(0x240A17), rgb(0x12060D)], specks: rgb(0xFF8A3D),
                motif: .castle, font: "Copperplate-Bold",
                symbols: ["flame.fill", "shield.fill", "bell.fill", "key.fill", "drop.fill", "moon.stars.fill", "hammer.fill", "map.fill"]
            ),
            "starwake": Theme(
                name: "Starwake",
                sky: [rgb(0x050A24), rgb(0x1B1F5E), rgb(0x5B2C8F)], light: rgb(0x9FD3FF),
                land: [rgb(0x22225A), rgb(0x141440), rgb(0x0A0A26)], specks: rgb(0xFFFFFF),
                motif: .planet, font: "Futura-CondensedExtraBold",
                symbols: ["sparkles", "globe.europe.africa.fill", "antenna.radiowaves.left.and.right", "star.fill", "moon.fill", "scope"]
            ),
            "neonrally": Theme(
                name: "Neon Rally Zero",
                sky: [rgb(0x12002E), rgb(0x5B0E7A), rgb(0xFF3D8B)], light: rgb(0xFFD23F),
                land: [rgb(0x1A0438), rgb(0x0E0222), rgb(0x06010F)], specks: rgb(0x34F5FF),
                motif: .synth, font: "AvenirNextCondensed-HeavyItalic",
                symbols: ["flag.checkered", "bolt.fill", "speedometer", "car.fill", "timer", "trophy.fill"]
            ),
            "mosswick": Theme(
                name: "Mosswick",
                sky: [rgb(0x9FE3D0), rgb(0xD9F5C5), rgb(0xFFF1C9)], light: rgb(0xFFFBE6),
                land: [rgb(0x7BC47F), rgb(0x4E9F63), rgb(0x2F7449)], specks: rgb(0xFFF5B5),
                motif: .grove, font: "ChalkboardSE-Bold",
                symbols: ["leaf.fill", "tree.fill", "ladybug.fill", "carrot.fill", "sun.max.fill", "heart.fill"]
            ),
            "hollowmere": Theme(
                name: "Hollowmere",
                sky: [rgb(0x0C1416), rgb(0x22363A), rgb(0x5E7A76)], light: rgb(0xE6EEE3),
                land: [rgb(0x1C2A2B), rgb(0x111A1B), rgb(0x080D0E)], specks: rgb(0xC9D8D2),
                motif: .fog, font: "Didot-Bold",
                symbols: ["eye.fill", "lock.fill", "candle.fill", "moon.fill", "key.fill", "cross.fill"]
            ),
            "lumentide": Theme(
                name: "Lumen Tide",
                sky: [rgb(0x041C3A), rgb(0x0B4F7A), rgb(0x2BA3B8)], light: rgb(0xFFE9A8),
                land: [rgb(0x08365C), rgb(0x062844), rgb(0x03182C)], specks: rgb(0xFFD66B),
                motif: .lanterns, font: "Optima-ExtraBlack",
                symbols: ["lightbulb.fill", "water.waves", "sparkle", "lamp.desk.fill", "puzzlepiece.fill", "circle.hexagongrid.fill"]
            ),
            "ironclad": Theme(
                name: "Ironclad Vanguard",
                sky: [rgb(0x101820), rgb(0x2C3E50), rgb(0xC0602A)], light: rgb(0xFF9F43),
                land: [rgb(0x2A3540), rgb(0x1A222B), rgb(0x0D1217)], specks: rgb(0xFFC48C),
                motif: .ridge, font: "Futura-CondensedExtraBold",
                symbols: ["shield.lefthalf.filled", "scope", "airplane", "flame.fill", "target", "medal.fill"]
            ),
            "skyforge": Theme(
                name: "Skyforge Tactics",
                sky: [rgb(0x3A7BD5), rgb(0x7FB8F0), rgb(0xD6ECFF)], light: rgb(0xFFFFFF),
                land: [rgb(0x5C8A5A), rgb(0x3E6B48), rgb(0x6B5440)], specks: rgb(0xFFFFFF),
                motif: .islands, font: "Baskerville-Bold",
                symbols: ["crown.fill", "flag.fill", "map.fill", "hammer.fill", "building.columns.fill", "cloud.fill"]
            ),
        ]
    }

    // MARK: Pictures

    private static func render(_ size: CGSize, opaque: Bool, scale: CGFloat = 1, _ draw: (CGContext, CGSize) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = opaque
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext, size) }
    }

    private static func icon(_ theme: Theme, dlc: Bool) -> UIImage {
        render(CGSize(width: 512, height: 512), opaque: true) { context, size in
            // The scene's middle, cropped square.
            context.saveGState()
            context.translateBy(x: -size.width * 0.39, y: 0)
            scene(theme, context, CGSize(width: size.width * 16 / 9, height: size.height))
            context.restoreGState()
            if dlc {
                context.setFillColor(UIColor.black.withAlphaComponent(0.35).cgColor)
                context.fill(CGRect(origin: .zero, size: size))
            }
            // The title along the bottom, over a shade.
            let shade = CGGradient(colorsSpace: nil, colors: [UIColor.black.withAlphaComponent(0).cgColor, UIColor.black.withAlphaComponent(0.6).cgColor] as CFArray, locations: [0, 1])!
            context.drawLinearGradient(shade, start: CGPoint(x: 0, y: size.height * 0.5), end: CGPoint(x: 0, y: size.height), options: [])
            let title = logo(theme)
            let width = size.width * 0.86
            let height = min(size.height * 0.34, width * title.size.height / title.size.width)
            let drawnWidth = height * title.size.width / title.size.height
            title.draw(in: CGRect(x: (size.width - drawnWidth) / 2, y: size.height - height - size.height * 0.07, width: drawnWidth, height: height))
        }
    }

    /// The game's name as its logo: white letters with a dark edge and a glow of its light; the
    /// part after a colon smaller, under it.
    private static func logo(_ theme: Theme) -> UIImage {
        let parts = theme.name.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let main = parts[0].uppercased()
        let sub = parts.count > 1 ? parts[1].uppercased() : nil
        let mainFont = UIFont(name: theme.font, size: 150) ?? .systemFont(ofSize: 150, weight: .black)
        let subFont = UIFont(name: theme.font, size: 56) ?? .systemFont(ofSize: 56, weight: .bold)
        let shadow = NSShadow()
        shadow.shadowColor = theme.light.withAlphaComponent(0.8)
        shadow.shadowBlurRadius = 24
        let mainAttributes: [NSAttributedString.Key: Any] = [
            .font: mainFont, .foregroundColor: UIColor.white, .strokeColor: UIColor.black.withAlphaComponent(0.55),
            .strokeWidth: -2.5, .shadow: shadow, .kern: 4,
        ]
        let subAttributes: [NSAttributedString.Key: Any] = [
            .font: subFont, .foregroundColor: theme.light, .shadow: shadow, .kern: 10,
        ]
        let mainSize = (main as NSString).size(withAttributes: mainAttributes)
        let subSize = sub.map { ($0 as NSString).size(withAttributes: subAttributes) } ?? .zero
        let padding: CGFloat = 40
        let size = CGSize(
            width: ceil(max(mainSize.width, subSize.width)) + padding * 2,
            height: ceil(mainSize.height + (sub == nil ? 0 : subSize.height + 8)) + padding * 2
        )
        return render(size, opaque: false) { _, size in
            (main as NSString).draw(at: CGPoint(x: (size.width - mainSize.width) / 2, y: padding), withAttributes: mainAttributes)
            if let sub {
                (sub as NSString).draw(at: CGPoint(x: (size.width - subSize.width) / 2, y: padding + mainSize.height + 8), withAttributes: subAttributes)
            }
        }
    }

    /// A badge in the game's colours with one of its symbols; the platinum (id 0) a crown on silver.
    private static func trophy(_ theme: Theme, id: Int) -> UIImage {
        render(CGSize(width: 256, height: 256), opaque: true) { context, size in
            // The platinum: a light crown on the game's night, ringed in silver.
            let colors = id == 0 ? [theme.sky[0], theme.sky[1]] : [theme.sky[1], theme.sky[2]]
            let gradient = CGGradient(colorsSpace: nil, colors: colors.map(\.cgColor) as CFArray, locations: [0, 1])!
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            let ring = CGRect(origin: .zero, size: size).insetBy(dx: 26, dy: 26)
            context.setStrokeColor(id == 0 ? rgb(0xDDE6F5).cgColor : UIColor.white.withAlphaComponent(0.35).cgColor)
            context.setLineWidth(id == 0 ? 10 : 6)
            context.strokeEllipse(in: ring)
            let name = id == 0 ? "crown.fill" : theme.symbols[id % theme.symbols.count]
            let config = UIImage.SymbolConfiguration(pointSize: 104, weight: .semibold)
            if let symbol = UIImage(systemName: name, withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                let fit = min(120 / symbol.size.width, 120 / symbol.size.height)
                let drawn = CGSize(width: symbol.size.width * fit, height: symbol.size.height * fit)
                context.setShadow(offset: CGSize(width: 0, height: 4), blur: 10, color: UIColor.black.withAlphaComponent(0.35).cgColor)
                symbol.draw(in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2, width: drawn.width, height: drawn.height))
            }
        }
    }

    private static func avatar() -> UIImage {
        render(CGSize(width: 512, height: 512), opaque: true) { context, size in
            let gradient = CGGradient(colorsSpace: nil, colors: [rgb(0x3573BA).cgColor, rgb(0x7B4FD6).cgColor] as CFArray, locations: [0, 1])!
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            let config = UIImage.SymbolConfiguration(pointSize: 260, weight: .bold)
            if let symbol = UIImage(systemName: "gamecontroller.fill", withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                symbol.draw(at: CGPoint(x: (size.width - symbol.size.width) / 2, y: (size.height - symbol.size.height) / 2))
            }
        }
    }

    // MARK: Scenes

    /// A wide scene: the sky, the light, three layers of land, the motif, specks in the air.
    private static func scene(_ theme: Theme, _ context: CGContext, _ size: CGSize) {
        var random = SeededRandom(seed: UInt64(abs(theme.name.hashValueStable)))
        let w = size.width, h = size.height
        let sky = CGGradient(colorsSpace: nil, colors: theme.sky.map(\.cgColor) as CFArray, locations: [0, 0.55, 1])!
        context.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: h), options: [])

        // The light: a sun, a moon or a glow, with a halo.
        let lightCenter = CGPoint(x: w * 0.62, y: h * (theme.motif == .synth ? 0.52 : 0.36))
        let lightRadius = h * (theme.motif == .planet ? 0.3 : 0.16)
        let halo = CGGradient(colorsSpace: nil, colors: [theme.light.withAlphaComponent(0.55).cgColor, theme.light.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(halo, startCenter: lightCenter, startRadius: lightRadius * 0.6, endCenter: lightCenter, endRadius: lightRadius * 3.2, options: [])

        switch theme.motif {
        case .planet:
            stars(context, size, count: 260, color: theme.specks, random: &random)
            planet(context, center: lightCenter, radius: lightRadius, theme: theme)
        case .synth:
            synthSun(context, center: lightCenter, radius: lightRadius * 1.6, theme: theme)
        default:
            context.setFillColor(theme.light.cgColor)
            context.fillEllipse(in: CGRect(x: lightCenter.x - lightRadius, y: lightCenter.y - lightRadius, width: lightRadius * 2, height: lightRadius * 2))
        }
        if theme.motif == .fog || theme.motif == .castle {
            stars(context, size, count: 90, color: UIColor.white.withAlphaComponent(0.7), random: &random)
        }

        // Three layers of land, far to near.
        for (index, color) in theme.land.enumerated() {
            let base = h * (0.62 + CGFloat(index) * 0.11)
            let roughness = h * (theme.motif == .grove ? 0.05 : 0.12) / CGFloat(index + 1)
            ridgeLine(context, size, base: base, roughness: roughness, color: color, jagged: theme.motif == .ridge || theme.motif == .castle, random: &random)
            if index == 0 {
                motif(theme, context, size, base: base, color: color, random: &random)
            }
        }

        if theme.motif == .synth { grid(context, size, color: theme.specks) }
        if theme.motif == .fog { fog(context, size) }
        // Specks: embers, fireflies, lantern light, dust.
        let count = theme.motif == .planet ? 0 : 70
        for _ in 0..<count {
            let x = random.next(in: 0...w), y = random.next(in: h * 0.15...h * 0.95)
            let r = random.next(in: 2...7)
            context.setFillColor(theme.specks.withAlphaComponent(random.next(in: 0.35...0.95)).cgColor)
            context.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
        }
        // A vignette, as key art has.
        let vignette = CGGradient(colorsSpace: nil, colors: [UIColor.black.withAlphaComponent(0).cgColor, UIColor.black.withAlphaComponent(0.45).cgColor] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(vignette, startCenter: CGPoint(x: w / 2, y: h / 2), startRadius: h * 0.4, endCenter: CGPoint(x: w / 2, y: h / 2), endRadius: w * 0.75, options: [.drawsAfterEndLocation])
    }

    private static func ridgeLine(_ context: CGContext, _ size: CGSize, base: CGFloat, roughness: CGFloat, color: UIColor, jagged: Bool, random: inout SeededRandom) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: size.height))
        var x: CGFloat = 0
        var previous = CGPoint(x: 0, y: base - random.next(in: 0...roughness))
        path.addLine(to: previous)
        while x < size.width {
            x += random.next(in: size.width * 0.05...size.width * 0.12)
            let point = CGPoint(x: min(x, size.width), y: base - random.next(in: 0...roughness))
            if jagged {
                path.addLine(to: point)
            } else {
                path.addQuadCurve(to: point, controlPoint: CGPoint(x: (previous.x + point.x) / 2, y: min(previous.y, point.y) - roughness * 0.6))
            }
            previous = point
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.close()
        context.setFillColor(color.cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
    }

    /// The game's own shapes on the far land.
    private static func motif(_ theme: Theme, _ context: CGContext, _ size: CGSize, base: CGFloat, color: UIColor, random: inout SeededRandom) {
        let w = size.width, h = size.height
        context.setFillColor(color.cgColor)
        switch theme.motif {
        case .castle:
            // A citadel of towers with spires, on the left.
            let towers: [(CGFloat, CGFloat, CGFloat)] = [(0.12, 0.05, 0.30), (0.18, 0.06, 0.42), (0.25, 0.045, 0.34), (0.31, 0.07, 0.24), (0.36, 0.04, 0.29)]
            for (x, width, height) in towers {
                let rect = CGRect(x: w * x, y: base - h * height, width: w * width, height: h * height + h * 0.05)
                context.fill(rect)
                context.move(to: CGPoint(x: rect.minX - w * 0.006, y: rect.minY))
                context.addLine(to: CGPoint(x: rect.midX, y: rect.minY - h * 0.09))
                context.addLine(to: CGPoint(x: rect.maxX + w * 0.006, y: rect.minY))
                context.fillPath()
                // Lit windows.
                context.setFillColor(theme.specks.withAlphaComponent(0.9).cgColor)
                for row in 0..<3 {
                    context.fill(CGRect(x: rect.midX - 4, y: rect.minY + h * 0.04 + CGFloat(row) * h * 0.06, width: 8, height: 14))
                }
                context.setFillColor(color.cgColor)
            }
        case .grove:
            for index in 0..<9 {
                let x = w * (0.05 + CGFloat(index) * 0.11) + random.next(in: -20...20)
                let r = h * random.next(in: 0.06...0.11)
                context.fillEllipse(in: CGRect(x: x - r, y: base - r * 2.2, width: r * 2, height: r * 2))
                context.fill(CGRect(x: x - r * 0.12, y: base - r * 0.6, width: r * 0.24, height: r * 0.8))
            }
        case .fog:
            // Bare trees.
            context.setStrokeColor(color.cgColor)
            context.setLineCap(.round)
            for index in 0..<6 {
                let x = w * (0.08 + CGFloat(index) * 0.17)
                let top = base - h * random.next(in: 0.18...0.32)
                context.setLineWidth(10)
                context.move(to: CGPoint(x: x, y: base + 10))
                context.addLine(to: CGPoint(x: x, y: top))
                context.strokePath()
                context.setLineWidth(5)
                for branch in 0..<4 {
                    let y = top + CGFloat(branch) * h * 0.04
                    let side: CGFloat = branch.isMultiple(of: 2) ? 1 : -1
                    context.move(to: CGPoint(x: x, y: y))
                    context.addLine(to: CGPoint(x: x + side * w * 0.03, y: y - h * 0.05))
                    context.strokePath()
                }
            }
        case .lanterns:
            for _ in 0..<16 {
                let x = random.next(in: 0...w), y = random.next(in: h * 0.2...base)
                let r = random.next(in: 10...26)
                let glow = CGGradient(colorsSpace: nil, colors: [theme.specks.withAlphaComponent(0.9).cgColor, theme.specks.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
                context.drawRadialGradient(glow, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r * 3, options: [])
                context.setFillColor(theme.light.cgColor)
                context.fill(CGRect(x: x - r * 0.5, y: y - r * 0.7, width: r, height: r * 1.4))
            }
        case .islands:
            for index in 0..<4 {
                let x = w * (0.1 + CGFloat(index) * 0.24), y = h * random.next(in: 0.28...0.5)
                let width = w * random.next(in: 0.1...0.18)
                context.setFillColor(theme.land[2].cgColor)
                context.move(to: CGPoint(x: x, y: y))
                context.addLine(to: CGPoint(x: x + width, y: y))
                context.addLine(to: CGPoint(x: x + width * 0.5, y: y + h * 0.16))
                context.fillPath()
                context.setFillColor(theme.land[0].cgColor)
                context.fillEllipse(in: CGRect(x: x - width * 0.05, y: y - h * 0.03, width: width * 1.1, height: h * 0.06))
            }
            // Clouds.
            context.setFillColor(UIColor.white.withAlphaComponent(0.8).cgColor)
            for _ in 0..<7 {
                let x = random.next(in: 0...w), y = random.next(in: h * 0.1...h * 0.4)
                for puff in 0..<4 {
                    let r = random.next(in: 30...60)
                    context.fillEllipse(in: CGRect(x: x + CGFloat(puff) * 40, y: y - r / 2, width: r * 2, height: r))
                }
            }
        case .ridge:
            // A watchtower on the ridge.
            let x = w * 0.22
            context.fill(CGRect(x: x, y: base - h * 0.38, width: w * 0.03, height: h * 0.4))
            context.fill(CGRect(x: x - w * 0.02, y: base - h * 0.42, width: w * 0.07, height: h * 0.05))
            context.setFillColor(theme.specks.cgColor)
            context.fill(CGRect(x: x + w * 0.005, y: base - h * 0.405, width: w * 0.02, height: h * 0.015))
        case .planet, .synth:
            break
        }
    }

    private static func stars(_ context: CGContext, _ size: CGSize, count: Int, color: UIColor, random: inout SeededRandom) {
        for _ in 0..<count {
            let x = random.next(in: 0...size.width), y = random.next(in: 0...size.height * 0.6)
            let r = random.next(in: 1...3.5)
            context.setFillColor(color.withAlphaComponent(random.next(in: 0.3...1)).cgColor)
            context.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
        }
    }

    private static func planet(_ context: CGContext, center: CGPoint, radius: CGFloat, theme: Theme) {
        let body = CGGradient(colorsSpace: nil, colors: [theme.light.cgColor, theme.sky[2].cgColor, theme.sky[0].cgColor] as CFArray, locations: [0, 0.6, 1])!
        context.saveGState()
        context.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.clip()
        context.drawRadialGradient(body, startCenter: CGPoint(x: center.x - radius * 0.4, y: center.y - radius * 0.4), startRadius: 0, endCenter: center, endRadius: radius * 1.2, options: [])
        context.restoreGState()
        // The ring.
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: -0.35)
        context.setStrokeColor(theme.light.withAlphaComponent(0.7).cgColor)
        context.setLineWidth(radius * 0.07)
        context.strokeEllipse(in: CGRect(x: -radius * 1.8, y: -radius * 0.42, width: radius * 3.6, height: radius * 0.84))
        context.restoreGState()
    }

    private static func synthSun(_ context: CGContext, center: CGPoint, radius: CGFloat, theme: Theme) {
        context.saveGState()
        context.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.clip()
        let sun = CGGradient(colorsSpace: nil, colors: [theme.light.cgColor, theme.sky[2].cgColor] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(sun, start: CGPoint(x: 0, y: center.y - radius), end: CGPoint(x: 0, y: center.y + radius), options: [])
        // The stripes across its lower half, in the sky's colour by the horizon.
        context.setFillColor(theme.sky[2].cgColor)
        for stripe in 0..<6 {
            let y = center.y + CGFloat(stripe) * radius * 0.17
            context.fill(CGRect(x: center.x - radius, y: y, width: radius * 2, height: radius * 0.04 * CGFloat(stripe + 1)))
        }
        context.restoreGState()
    }

    private static func grid(_ context: CGContext, _ size: CGSize, color: UIColor) {
        let horizon = size.height * 0.7
        context.setStrokeColor(color.withAlphaComponent(0.7).cgColor)
        context.setLineWidth(3)
        for index in -12...12 {
            context.move(to: CGPoint(x: size.width / 2 + CGFloat(index) * 30, y: horizon))
            context.addLine(to: CGPoint(x: size.width / 2 + CGFloat(index) * 260, y: size.height))
        }
        var y = horizon
        var step: CGFloat = 8
        while y < size.height {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: size.width, y: y))
            y += step
            step *= 1.35
        }
        context.strokePath()
    }

    private static func fog(_ context: CGContext, _ size: CGSize) {
        let fog = CGGradient(colorsSpace: nil, colors: [UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.withAlphaComponent(0.22).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 0.5, 1])!
        context.drawLinearGradient(fog, start: CGPoint(x: 0, y: size.height * 0.55), end: CGPoint(x: 0, y: size.height * 0.95), options: [])
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// The same numbers on every run, so a game's scene is always the same.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func nextUInt() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 11
    }

    mutating func next(in range: ClosedRange<CGFloat>) -> CGFloat {
        let unit = CGFloat(nextUInt() % 1_000_000) / 1_000_000
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}

private extension String {
    /// `hashValue` changes between launches; the scenes must not.
    var hashValueStable: Int {
        var hash: UInt64 = 5381
        for byte in utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return Int(truncatingIfNeeded: hash & 0x7FFF_FFFF)
    }
}

/// The drawn pictures, kept: a scene is drawn once.
private final class ImageCache: @unchecked Sendable {
    private let lock = NSLock()
    private var images: [String: UIImage] = [:]

    func image(_ key: String) -> UIImage? {
        lock.withLock { images[key] }
    }

    func keep(_ image: UIImage, for key: String) {
        lock.withLock { images[key] = image }
    }
}
