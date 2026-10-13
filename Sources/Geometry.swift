import CoreGraphics

enum CaptureGeometry {
    static func plan(selection: CGRect, screen: CGRect, scale: CGFloat) -> (rect: CGRect, width: Int, height: Int)? {
        guard scale.isFinite, scale > 0 else { return nil }
        let clipped = selection.standardized.intersection(screen)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        let left = floor((clipped.minX - screen.minX) * scale)
        let top = floor((screen.maxY - clipped.maxY) * scale)
        let right = min(ceil((clipped.maxX - screen.minX) * scale), floor(screen.width * scale))
        let bottom = min(ceil((screen.maxY - clipped.minY) * scale), floor(screen.height * scale))
        guard right > left, bottom > top else { return nil }
        return (CGRect(x: left / scale, y: top / scale, width: (right - left) / scale, height: (bottom - top) / scale), Int(right - left), Int(bottom - top))
    }
}
