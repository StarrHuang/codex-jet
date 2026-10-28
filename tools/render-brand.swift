import AppKit
import SwiftUI

/// 直接从应用共用的矢量组件导出 ICNS 母版，避免各入口图形漂移。
@main struct RenderBrand {
    @MainActor static func main() throws {
        let renderer = ImageRenderer(content: QuotaAppIcon().frame(width: 1024, height: 1024))
        renderer.scale = 1
        let image = NSBitmapImageRep(cgImage: renderer.cgImage!)
        try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
