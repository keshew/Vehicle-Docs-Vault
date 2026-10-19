import SwiftUI
import UIKit
import ImageIO
import CoreGraphics
import PDFKit

// UIKit images stay immutable after rendering and can be handed back to the UI.
struct VaultRenderedImage: @unchecked Sendable {
    let image: UIImage
}

struct VaultLoadedPDF: @unchecked Sendable {
    // A document is handed to one reader and is never cached or reused by the actor.
    let document: PDFDocument
}

actor VaultMediaRenderer {
    static let shared = VaultMediaRenderer()
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.totalCostLimit = 48 * 1024 * 1024
        cache.countLimit = 100
    }

    func image(at url: URL, pixels: Int, isPDF: Bool) -> VaultRenderedImage? {
        let edge = max(64, min(pixels, 4096))
        let key = "\(url.path)|\(edge)" as NSString
        if let image = cache.object(forKey: key) { return VaultRenderedImage(image: image) }
        guard !Task.isCancelled else { return nil }
        let rendered: UIImage? = autoreleasepool {
            if isPDF { return pdfPreview(url, pixels: edge) }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: edge
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: thumbnail)
        }
        guard !Task.isCancelled, let rendered else { return nil }
        if edge <= 1600, let cgImage = rendered.cgImage {
            cache.setObject(rendered, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        }
        return VaultRenderedImage(image: rendered)
    }

    func openPDF(at url: URL) -> VaultLoadedPDF? {
        guard !Task.isCancelled, let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else { return nil }
        return VaultLoadedPDF(document: document)
    }

    private func pdfPreview(_ url: URL, pixels: Int) -> UIImage? {
        guard let document = CGPDFDocument(url as CFURL), !document.isEncrypted || document.isUnlocked,
              let page = document.page(at: 1) else { return nil }
        let box = page.getBoxRect(.cropBox)
        guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else { return nil }
        let rotated = abs(Int(page.rotationAngle) % 180) == 90
        let pageWidth = rotated ? box.height : box.width
        let pageHeight = rotated ? box.width : box.height
        let scale = CGFloat(pixels) / max(pageWidth, pageHeight)
        let width = max(1, Int((pageWidth * scale).rounded(.up)))
        let height = max(1, Int((pageHeight * scale).rounded(.up)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        context.setFillColor(UIColor.white.cgColor)
        context.fill(rect)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { return nil }
        return UIImage(cgImage: image)
    }
}

struct VaultMediaImage<Placeholder: View>: View {
    var url: URL
    var pixels: Int = 900
    var isPDF = false
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: Placeholder
    @State private var loaded: VaultRenderedImage?
    @State private var loadedKey = ""
    private var key: String { "\(url.path)|\(pixels)|\(isPDF)" }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let loaded, loadedKey == key {
                    Image(uiImage: loaded.image).resizable().aspectRatio(contentMode: contentMode)
                } else { placeholder }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .task(id: key) {
            let request = key
            let result = await VaultMediaRenderer.shared.image(at: url, pixels: pixels, isPDF: isPDF)
            guard !Task.isCancelled, request == key else { return }
            loaded = result
            loadedKey = request
        }
    }
}

struct VaultImageReader: View {
    var url: URL
    @State private var image: VaultRenderedImage?
    @State private var loading = true

    var body: some View {
        Group {
            if let image { ZoomImage(image: image.image).background(Color.black) }
            else if loading { ProgressView("Opening image…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { EmptyVault(symbol: "exclamationmark.triangle", title: "Unable to open this image", message: "The file may be missing or damaged. Restore a complete backup to recover it.") }
        }
        .task(id: url) {
            loading = true
            image = nil
            let result = await VaultMediaRenderer.shared.image(at: url, pixels: 4096, isPDF: false)
            guard !Task.isCancelled else { return }
            image = result
            loading = false
        }
    }
}
