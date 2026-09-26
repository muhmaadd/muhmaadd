import AppKit
import ScreenCaptureKit

/// A screenshot of part of one display.
struct CapturedImage: @unchecked Sendable {
    let image: CGImage
    /// The captured area in global Cocoa coordinates (origin bottom-left).
    let screenFrame: CGRect
    /// Image pixels per screen point.
    let scale: CGFloat
    let isFullScreen: Bool

    var pointSize: CGSize { screenFrame.size }
}

enum CaptureError: LocalizedError {
    case permissionDenied
    case displayNotFound

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "لا يملك ترجِم إذن تسجيل الشاشة."
        case .displayNotFound: "تعذّر العثور على الشاشة المطلوبة."
        }
    }
}

enum ScreenCapture {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt the first time; returns whether access is granted.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    /// Captures `rect` (in the screen's own coordinates, points, origin top-left),
    /// or the whole screen when `rect` is nil. Tarjem's own windows are excluded.
    static func capture(screen: NSScreen, rect: CGRect?) async throws -> CapturedImage {
        guard let displayID = screen.displayID else { throw CaptureError.displayNotFound }
        let screenFrame = screen.frame

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw hasPermission ? error : CaptureError.permissionDenied
        }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let filter: SCContentFilter
        if let ownApp = content.applications.first(where: { $0.processID == ownPID }) {
            filter = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }

        let scale = CGFloat(filter.pointPixelScale)
        let area = rect ?? CGRect(origin: .zero, size: screenFrame.size)

        let configuration = SCStreamConfiguration()
        if rect != nil { configuration.sourceRect = area }
        configuration.width = max(1, Int((area.width * scale).rounded()))
        configuration.height = max(1, Int((area.height * scale).rounded()))
        configuration.showsCursor = false
        configuration.captureResolution = .best

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)

        let globalFrame = CGRect(
            x: screenFrame.minX + area.minX,
            y: screenFrame.maxY - area.maxY,
            width: area.width,
            height: area.height
        )
        return CapturedImage(image: image, screenFrame: globalFrame, scale: scale, isFullScreen: rect == nil)
    }
}
