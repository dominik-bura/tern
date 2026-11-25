#!/usr/bin/env swift
import AppKit

// The editable SVGs are the source of truth. The app master includes the
// standard 824/1024 macOS tile footprint; do not crop its transparent margins.
// librsvg preserves the vector shading and texture. AppKit produces native sizes.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let vectors = root.appendingPathComponent("assets/vector")
let assets = root.appendingPathComponent("App/Assets")
let build = root.appendingPathComponent("build")
let manager = FileManager.default
try manager.createDirectory(at: assets, withIntermediateDirectories: true)
try manager.createDirectory(at: build, withIntermediateDirectories: true)

let renderCandidates = [ProcessInfo.processInfo.environment["TERN_SVG_RENDERER"]].compactMap { $0 }
    + ["/opt/homebrew/bin/rsvg-convert", "/usr/local/bin/rsvg-convert", "/usr/bin/rsvg-convert"]
guard let renderer = renderCandidates.first(where: { manager.isExecutableFile(atPath: $0) }) else {
    FileHandle.standardError.write(Data("Icon regeneration requires librsvg (brew install librsvg), or TERN_SVG_RENDERER. Normal app builds use the generated assets already in App/Assets.\n".utf8))
    exit(1)
}
let masterSVG = vectors.appendingPathComponent("tern-switch-icon.svg")
let masterPNG = assets.appendingPathComponent("TernAppIcon-1024.png")
let process = Process()
process.executableURL = URL(fileURLWithPath: renderer)
process.arguments = ["--width", "1024", "--height", "1024", masterSVG.path, "--output", masterPNG.path]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("SVG icon rendering failed") }
try Data(contentsOf: masterSVG).write(to: assets.appendingPathComponent("TernAppIcon.svg"))
try Data(contentsOf: vectors.appendingPathComponent("tern-fold-logo.svg")).write(to: assets.appendingPathComponent("TernLogo.svg"))
try Data(contentsOf: vectors.appendingPathComponent("tern-switch-mark.svg")).write(to: assets.appendingPathComponent("TernLogoMonochrome.svg"))
try Data(contentsOf: masterPNG).write(to: vectors.appendingPathComponent("tern-switch-icon-preview.png"))

// Use the dedicated solid silhouette for the 22×18-point menu-bar image.
// Its flat folded-plane silhouette stays legible at small sizes; macOS supplies the tint.
let markSource = try String(contentsOf: vectors.appendingPathComponent("tern-menu-bar-mark.svg"), encoding: .utf8)
let menuSVG = markSource
    .replacingOccurrences(of: "currentColor", with: "#000")
let menuURL = assets.appendingPathComponent("TernMark.svg")
try Data(menuSVG.utf8).write(to: menuURL)
guard let appImage = NSImage(contentsOf: masterPNG) else { fatalError("Generated app icon could not be loaded") }

func render(_ image: NSImage, width: Int, height: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw CocoaError(.fileWriteUnknown) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    return data
}

try render(appImage, width: 320, height: 320).write(to: vectors.appendingPathComponent("tern-switch-icon-preview-320.png"))

for scale in 1...3 {
    let suffix = scale == 1 ? "" : "@\(scale)x"
    // Render masks with the same SVG engine as the app artwork. CoreSVG does
    // not preserve the overlap knockouts when AppKit loads the SVG directly.
    let menuRender = Process()
    menuRender.executableURL = URL(fileURLWithPath: renderer)
    menuRender.arguments = ["--width", "\(22 * scale)", "--height", "\(18 * scale)", menuURL.path, "--output", assets.appendingPathComponent("TernMenuBarIconTemplate\(suffix).png").path]
    try menuRender.run(); menuRender.waitUntilExit()
    guard menuRender.terminationStatus == 0 else { fatalError("SVG menu-bar rendering failed at \(scale)x") }
}
let iconset = build.appendingPathComponent("Tern.iconset")
try manager.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(appImage, width: size, height: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(appImage, width: size * 2, height: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", assets.appendingPathComponent("Tern.icns").path]
try iconutil.run(); iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Generated interlocking folded-plane app icon and native menu-bar assets from the SVG masters.")
