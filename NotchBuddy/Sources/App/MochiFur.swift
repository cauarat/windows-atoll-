import CoreGraphics
import SwiftUI

/// The plush surface a shaped Mochi is made of.
///
/// The reference art gets this from an SVG filter — turbulence lit from one
/// side and multiplied back over the shape — and none of that exists in a
/// `GraphicsContext`. What does survive the translation is the part that
/// matters: a fine, even, slightly directional grain that breaks up the
/// gradient and reads as fibre rather than as plastic.
///
/// One tile, built once, shared by every engine and every colour. It is drawn
/// multiplied inside the body, so a cyan pal and an orange one get the same
/// fibres in their own hue without a second tile. Nothing is built until
/// somebody first draws a shaped body, so a user who never opens the picker
/// never pays for any of it.
enum MochiFur {
    /// Deterministic noise in 0…1, from an integer hash.
    ///
    /// An integer hash and not `sin(i * 127.1) * 43758.5`: float `sin` differs
    /// in its last bits between platforms, and the parity suite compares these
    /// values against the TypeScript twin's.
    ///
    /// It lives here rather than on `BotEngine` because the engine is
    /// main-actor isolated and the tile is built lazily off it.
    static func hash(_ i: Int, _ seed: UInt32) -> CGFloat {
        var h = UInt32(truncatingIfNeeded: i) &* 0x9E37_79B9 &+ seed
        h ^= h >> 16; h = h &* 0x85EB_CA6B
        h ^= h >> 13; h = h &* 0xC2B2_AE35; h ^= h >> 16
        return CGFloat(h) / CGFloat(UInt32.max)
    }

    /// Small on purpose: at 96 px it tiles invisibly under a 60-pt body and
    /// costs 9 KB. Bigger buys nothing the eye can find.
    static let size = 96

    /// Value noise on a wrapping grid, so the tile has no seam.
    ///
    /// Built on `hash`, so the tile and the ragged edge come from one source.
    static func noise(_ x: Int, _ y: Int, cell: Int) -> CGFloat {
        let gx = x / cell, gy = y / cell
        let fx = CGFloat(x % cell) / CGFloat(cell)
        let fy = CGFloat(y % cell) / CGFloat(cell)
        let wrap = size / cell
        func corner(_ i: Int, _ j: Int) -> CGFloat {
            hash(((j % wrap) &* 57) &+ (i % wrap), 0x5EED_1234)
        }
        // Smoothstep between corners: a linear blend leaves a visible lattice.
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let top = corner(gx, gy) + (corner(gx + 1, gy) - corner(gx, gy)) * sx
        let bot = corner(gx, gy + 1) + (corner(gx + 1, gy + 1) - corner(gx, gy + 1)) * sx
        return top + (bot - top) * sy
    }

    /// 0…255 grey, as the tile is written out. Shared with the parity dump.
    static func sample(_ x: Int, _ y: Int) -> UInt8 {
        let v = noise(x, y, cell: 12) * 0.62 + noise(x, y, cell: 4) * 0.38
        // Centred near white so multiplying darkens only slightly: this is a
        // texture on the body, not a shadow over it.
        return UInt8(clamping: Int(((0.80 + 0.26 * (v - 0.5)) * 255).rounded()))
    }

    static let image: Image = {
        let n = size
        var bytes = [UInt8](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n { bytes[y * n + x] = sample(x, y) }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cg = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 8,
                         bytesPerRow: n, space: CGColorSpaceCreateDeviceGray(),
                         bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                         decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        return Image(decorative: cg, scale: 1)
    }()
}
