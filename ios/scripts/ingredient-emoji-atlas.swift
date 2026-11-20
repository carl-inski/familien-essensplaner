#!/usr/bin/env swift

import AppKit
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Run from the repository root. Review the art in each atlas before importing it.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalogURL = root.appending(path: "ios/Gnocchi/Resources/ingredient-emojis.txt")
let iconFolder = root.appending(path: "ios/IngredientEmojis", directoryHint: .isDirectory)
let fileManager = FileManager.default
let iconSize = 96

struct PipelineError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

struct Atlas: Codable {
    let number: Int
    let terms: [String]
    let grid: Int?
    let prompt: String
}

func key(_ name: String) -> String {
    name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        .replacingOccurrences(of: "ß", with: "ss")
        .filter { $0.isLetter || $0.isNumber }
}

func sourceTerms() throws -> [String] {
    let text = try String(contentsOf: catalogURL, encoding: .utf8)
    let terms = text.split(whereSeparator: \.isNewline).flatMap { line -> [String] in
        guard !line.hasPrefix("#"), let names = line.split(separator: "\t").dropFirst().first else { return [] }
        return names.split(separator: "|").map(String.init)
    }
    guard !terms.isEmpty, Set(terms.map(key)).count == terms.count else {
        throw PipelineError("Der Katalog muss für jeden Begriff einen eindeutigen Dateinamen ergeben.")
    }
    return terms
}

func iconURL(_ term: String) -> URL {
    iconFolder.appending(path: key(term) + ".png")
}

func makePlan(_ pending: [String], grid: Int) -> [Atlas] {
    let cellCount = grid * grid
    let centers = (0..<grid).map { String(format: "%.1f%%", (Double($0) + 0.5) * 100 / Double(grid)) }
    return stride(from: 0, to: pending.count, by: cellCount).enumerated().map { number, offset in
        let terms = Array(pending.dropFirst(offset).prefix(cellCount))
        let cells = terms + Array(repeating: "leave blank", count: cellCount - terms.count)
        let rows = stride(from: 0, to: cellCount, by: grid).enumerated().map { row, start in
            "Row \(row + 1), left to right: " + cells[start..<(start + grid)].joined(separator: " | ")
        }
        return Atlas(number: number + 1, terms: terms, grid: grid, prompt: """
            Draw a square production sprite atlas for a German cooking app, exactly \(grid) columns and \(grid) rows.
            Use a genuinely transparent RGBA background. Each ingredient is a separate photoreal mini food emoji,
            three-quarter angle, soft studio light, matching visual scale. The object centers are
            \(centers.joined(separator: ", ")) of width and height. Leave 15% transparent padding inside every edge of each cell.
            No text, labels, grid lines or decorative marks. Preserve real differences in form, color and preparation.
            Render exactly these distinct ingredients:
            \(rows.joined(separator: "\n"))
            """)
    }
}

func readImage(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw PipelineError("Bild konnte nicht gelesen werden: \(url.lastPathComponent)")
    }
    return image
}

func makeContext(width: Int, height: Int) throws -> CGContext {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw PipelineError("Bildkontext konnte nicht erstellt werden.") }
    return context
}

func bounds(in image: CGImage) throws -> (rect: CGRect, coverage: Double, clips: Bool) {
    let width = image.width
    let height = image.height
    let context = try makeContext(width: width, height: height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else {
        throw PipelineError("Alpha-Kanal konnte nicht gelesen werden.")
    }
    var minX = width, minY = height, maxX = -1, maxY = -1
    var total = 0, edge = 0
    for y in 0..<height {
        for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 40 {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
            total += 1
            if x < 2 || y < 2 || x >= width - 2 || y >= height - 2 { edge += 1 }
        }
    }
    if total == 0 { return (.null, 0, false) }
    return (CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1),
            Double(total) / Double(width * height), edge > 12)
}

func normalizedIcon(_ image: CGImage, name: String) throws -> Data {
    let alpha = try bounds(in: image)
    guard alpha.coverage >= 0.045, alpha.coverage <= 0.78 else {
        throw PipelineError("\(name): Das Motiv fehlt oder hat zu wenig transparenten Hintergrund.")
    }
    guard !alpha.clips else { throw PipelineError("\(name): Das Motiv berührt den Zellenrand.") }
    let canvas = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    guard let trimmed = image.cropping(to: alpha.rect.insetBy(dx: -2, dy: -2).intersection(canvas)) else {
        throw PipelineError("\(name): Motiv konnte nicht zugeschnitten werden.")
    }
    let context = try makeContext(width: iconSize, height: iconSize)
    context.interpolationQuality = .high
    let scale = Double(iconSize - 8) / Double(max(trimmed.width, trimmed.height))
    let width = Double(trimmed.width) * scale
    let height = Double(trimmed.height) * scale
    context.draw(trimmed, in: CGRect(x: (Double(iconSize) - width) / 2, y: (Double(iconSize) - height) / 2,
                                    width: width, height: height))
    guard let rendered = context.makeImage() else { throw PipelineError("Motiv konnte nicht gerendert werden.") }
    let data = NSMutableData()
    guard let output = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
        throw PipelineError("PNG konnte nicht angelegt werden.")
    }
    CGImageDestinationAddImage(output, rendered, nil)
    guard CGImageDestinationFinalize(output) else { throw PipelineError("PNG konnte nicht gespeichert werden.") }
    return data as Data
}

func digest(_ data: Data) -> SHA256.Digest { SHA256.hash(data: data) }

func importAtlas(path: String, terms: [String], grid: Int) throws {
    let image = try readImage(URL(fileURLWithPath: path))
    let shortEdge = min(image.width, image.height)
    guard shortEdge >= 384, Double(max(image.width, image.height)) / Double(shortEdge) <= 1.8 else {
        throw PipelineError("Erwartet wird ein regelmäßiger Bildbogen mit mindestens 384 Pixeln pro Kante.")
    }
    var prepared: [(URL, Data)] = []
    var fingerprints: Set<SHA256.Digest> = []
    var rejected: [String] = []
    for (index, term) in terms.enumerated() {
        let x = index % grid * image.width / grid
        let y = index / grid * image.height / grid
        let right = (index % grid + 1) * image.width / grid
        let bottom = (index / grid + 1) * image.height / grid
        let destination = iconURL(term)
        if fileManager.fileExists(atPath: destination.path) { continue }
        do {
            guard let cell = image.cropping(to: CGRect(x: x, y: y, width: right - x, height: bottom - y)) else {
                throw PipelineError("\(term): Zelle fehlt.")
            }
            let png = try normalizedIcon(cell, name: term)
            guard fingerprints.insert(digest(png)).inserted else {
                throw PipelineError("\(term): Identische Motive im selben Atlas gefunden.")
            }
            prepared.append((destination, png))
        } catch {
            rejected.append(error.localizedDescription)
        }
    }
    if rejected.count > max(2, terms.count / 4) {
        throw PipelineError("Ungültiger Atlas. " + rejected.joined(separator: " "))
    }
    try fileManager.createDirectory(at: iconFolder, withIntermediateDirectories: true)
    for (url, data) in prepared { try data.write(to: url, options: .atomic) }
    print("\(prepared.count) Motive importiert.")
    if !rejected.isEmpty {
        throw PipelineError(rejected.joined(separator: " "))
    }
}

do {
    let terms = try sourceTerms()
    let pending = terms.filter { !fileManager.fileExists(atPath: iconURL($0).path) }
    let arguments = Array(CommandLine.arguments.dropFirst())
    switch arguments.first {
    case "plan" where (1...2).contains(arguments.count):
        guard let grid = Int(arguments.dropFirst().first ?? "4"), (2...4).contains(grid) else {
            throw PipelineError("Das Raster muss zwischen 2 und 4 liegen.")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(makePlan(pending, grid: grid)), as: UTF8.self))
    case "import" where arguments.count == 4:
        let atlasPath = arguments[1]
        let plan = try JSONDecoder().decode([Atlas].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])))
        guard let number = Int(arguments[3]), let atlas = plan.first(where: { $0.number == number }) else {
            throw PipelineError("Atlasnummer ist ungültig.")
        }
        let grid = atlas.grid ?? 4
        guard (2...4).contains(grid), (1...(grid * grid)).contains(atlas.terms.count),
              Set(atlas.terms).isSubset(of: Set(terms)), Set(atlas.terms).count == atlas.terms.count else {
            throw PipelineError("Atlasnummer oder Zuordnung ist ungültig.")
        }
        try importAtlas(path: atlasPath, terms: atlas.terms, grid: grid)
    case "single" where arguments.count == 3:
        let name = arguments[2]
        guard terms.contains(name), !fileManager.fileExists(atPath: iconURL(name).path) else {
            throw PipelineError("Der Begriff fehlt im Katalog oder hat bereits ein eigenes Motiv.")
        }
        let image = try readImage(URL(fileURLWithPath: arguments[1]))
        let png = try normalizedIcon(image, name: name)
        try fileManager.createDirectory(at: iconFolder, withIntermediateDirectories: true)
        try png.write(to: iconURL(name), options: .atomic)
        print("\(name): Motiv importiert.")
    case "validate" where arguments.count == 1:
        var fingerprints: Set<SHA256.Digest> = []
        for term in terms where fileManager.fileExists(atPath: iconURL(term).path) {
            let url = iconURL(term)
            let image = try readImage(url)
            let alpha = try bounds(in: image)
            guard image.width == iconSize, image.height == iconSize, alpha.coverage > 0, !alpha.clips,
                  fingerprints.insert(digest(try Data(contentsOf: url))).inserted else {
                throw PipelineError("\(term): Falsches Format, abgeschnittenes oder identisches Motiv.")
            }
        }
        print("\(terms.count - pending.count)/\(terms.count) Motive geprüft.")
        if !pending.isEmpty { exit(2) }
    default:
        throw PipelineError("Verwendung: ingredient-emoji-atlas.swift plan [2|3|4] | import ATLAS.png PLAN.json NUMMER | single BILD.png BEGRIFF | validate")
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
