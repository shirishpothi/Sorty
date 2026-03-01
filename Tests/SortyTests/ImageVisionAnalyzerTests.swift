import XCTest
import AppKit
import ImageIO
import CryptoKit
@testable import SortyLib

final class ImageVisionAnalyzerTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        ImageVisionAnalyzer.clearSharedCache()
    }

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        ImageVisionAnalyzer.clearSharedCache()
    }

    func testPrepareImageForVisionResizesLargeImage() async throws {
        let imageURL = tempDirectory.appendingPathComponent("large.png")
        try createPNG(at: imageURL, width: 2000, height: 1000)

        let analyzer = ImageVisionAnalyzer()
        let data = await analyzer.prepareImageForVision(at: imageURL)

        XCTAssertNotNil(data)
        let dimensions = imageDimensions(from: data)
        XCTAssertEqual(dimensions?.width, 1024)
        XCTAssertEqual(dimensions?.height, 512)
    }

    func testPrepareImageForVisionKeepsSmallImageSize() async throws {
        let imageURL = tempDirectory.appendingPathComponent("small.png")
        try createPNG(at: imageURL, width: 100, height: 100)

        let analyzer = ImageVisionAnalyzer()
        let data = await analyzer.prepareImageForVision(at: imageURL)

        XCTAssertNotNil(data)
        let dimensions = imageDimensions(from: data)
        XCTAssertEqual(dimensions?.width, 100)
        XCTAssertEqual(dimensions?.height, 100)
    }

    func testPrepareImagesForVisionProcessesMultipleImages() async throws {
        let urls = [
            tempDirectory.appendingPathComponent("a.png"),
            tempDirectory.appendingPathComponent("b.png"),
            tempDirectory.appendingPathComponent("c.png")
        ]
        try createPNG(at: urls[0], width: 120, height: 120)
        try createPNG(at: urls[1], width: 200, height: 100)
        try createPNG(at: urls[2], width: 80, height: 180)

        let analyzer = ImageVisionAnalyzer()
        let result = await analyzer.prepareImagesForVision(urls: urls)

        XCTAssertEqual(result.count, 3)
        XCTAssertNotNil(result[urls[0]])
        XCTAssertNotNil(result[urls[1]])
        XCTAssertNotNil(result[urls[2]])
    }

    func testPrepareImageForVisionHandlesMissingAndCorruptedFile() async throws {
        let analyzer = ImageVisionAnalyzer()

        let missingURL = tempDirectory.appendingPathComponent("missing.jpg")
        let missingResult = await analyzer.prepareImageForVision(at: missingURL)
        XCTAssertNil(missingResult)

        let corruptedURL = tempDirectory.appendingPathComponent("corrupted.jpg")
        try Data("not-an-image".utf8).write(to: corruptedURL)
        let corruptedResult = await analyzer.prepareImageForVision(at: corruptedURL)
        XCTAssertNil(corruptedResult)
    }

    func testPrepareImageForVisionCachesAndClearCacheRemovesFiles() async throws {
        let imageURL = tempDirectory.appendingPathComponent("cache.png")
        try createPNG(at: imageURL, width: 256, height: 256)

        let analyzer = ImageVisionAnalyzer()
        let first = await analyzer.prepareImageForVision(at: imageURL)
        XCTAssertNotNil(first)

        guard let cachedFileURL = cacheFileURL(for: imageURL) else {
            XCTFail("Failed to resolve expected cache file path")
            return
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: cachedFileURL.path))

        analyzer.clearVisionCache()
        XCTAssertFalse(FileManager.default.fileExists(atPath: cachedFileURL.path))
    }

    private func createPNG(at url: URL, width: Int, height: Int) throws {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let bitmap = rep else {
            XCTFail("Failed to create bitmap")
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to create PNG representation")
            return
        }
        try data.write(to: url)
    }

    private func imageDimensions(from data: Data?) -> (width: Int, height: Int)? {
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int else {
            return nil
        }
        return (width, height)
    }

    private func cacheFileURL(for imageURL: URL) -> URL? {
        let values = try? imageURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modTime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = values?.fileSize ?? 0
        let input = "\(imageURL.path)|\(modTime)|\(fileSize)"
        let digest = SHA256.hash(data: Data(input.utf8))
        let key = digest.compactMap { String(format: "%02x", $0) }.joined()

        guard let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sorty")
            .appendingPathComponent("VisionCache", isDirectory: true) else {
            return nil
        }
        return cacheDirectory.appendingPathComponent("\(key).jpg")
    }
}
