import AppKit
import Metal
import SceneKit
import ResetCore
import simd

/// Depth-tested folded paper; the capacity bottle is composited separately.
@MainActor final class PaperPlane3DRenderer: ObservableObject {
    struct Frame { let image: CGImage; let planeBounds: CGRect }
    private struct Key: Equatable {
        let size: CGSize
        let lift: Double
        let speed: Double
        let phase: Double
        let launch: PaperPlaneLaunchPose?
    }
    let scene = SCNScene()
    let vehicle = SCNNode()
    let plane = PaperPlaneGeometry.make()
    private let renderer: SCNRenderer
    private var cached: (Key, Frame)?
    private(set) var renderCount = 0
    init() {
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Paper plane 3D requires Metal") }
        renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        scene.background.contents = NSColor.clear
        scene.lightingEnvironment.contents = Self.studioEnvironment()
        scene.lightingEnvironment.intensity = 0.4
        let camera = SCNNode()
        let lens = SCNCamera()
        lens.fieldOfView = 24.6
        lens.zNear = 0.1
        lens.zFar = 60
        lens.wantsHDR = true
        lens.exposureOffset = -0.45
        lens.wantsExposureAdaptation = false
        camera.camera = lens
        camera.position = SCNVector3(-6.4, 7, 10)
        camera.look(at: SCNVector3(0, 1.8, 0))
        scene.rootNode.addChildNode(camera)
        renderer.pointOfView = camera
        addLight(position: SCNVector3(-3, 7, 5), intensity: 650, color: .white)
        addLight(position: SCNVector3(4, 4, -5), intensity: 450,
                 color: NSColor(red: 0.77, green: 0.85, blue: 1, alpha: 1))
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 130
        scene.rootNode.addChildNode(ambient)
        vehicle.addChildNode(plane)
        scene.rootNode.addChildNode(vehicle)
    }
    func frame(size: CGSize, lift: Double, speed: Double, phase: Double,
               launch: PaperPlaneLaunchPose?) -> Frame {
        let key = Key(size: size, lift: lift, speed: speed, phase: speed > 0 || launch != nil ? phase : 0, launch: launch)
        if let cached, cached.0 == key { return cached.1 }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        let cruiseBank = speed > 0 ? sin(phase * 0.10) * 5 : 0
        vehicle.simdOrientation = Self.orientation(pitch: launch?.pitchDegrees ?? 0,
            roll: launch?.bankDegrees ?? cruiseBank, yaw: launch?.yawDegrees ?? 0)
        // The same normalized balance-to-height and measured-rate-to-speed mappings are retained.
        vehicle.simdPosition = SIMD3(Float(-speed * 0.10), Float(0.36 + lift * 2.35), 0)
        if launch != nil {
            let minimum = corners().map { vehicle.simdConvertPosition($0, to: nil).y }.min()!
            if minimum < 0.015 { vehicle.position.y += CGFloat(0.015 - minimum) }
        }
        SCNTransaction.commit()
        let pixels = CGSize(width: ceil(size.width * 2), height: ceil(size.height * 2))
        let snapshot = renderer.snapshot(atTime: 0, with: pixels, antialiasingMode: .multisampling4X)
        var rect = CGRect(origin: .zero, size: pixels)
        guard let image = snapshot.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            fatalError("Paper plane snapshot has no pixels")
        }
        let points = corners().map { corner -> CGPoint in
            let p = renderer.projectPoint(vehicle.convertPosition(SCNVector3(corner), to: nil))
            return CGPoint(x: CGFloat(p.x) / 2, y: size.height - CGFloat(p.y) / 2)
        }
        let bounds = CGRect(x: points.map(\.x).min()!, y: points.map(\.y).min()!,
            width: points.map(\.x).max()! - points.map(\.x).min()!,
            height: points.map(\.y).max()! - points.map(\.y).min()!)
        let frame = Frame(image: image, planeBounds: bounds)
        cached = (key, frame)
        renderCount += 1
        return frame
    }
    static func orientation(pitch: Double, roll: Double, yaw: Double) -> simd_quatf {
        let radians = Float.pi / 180
        return simd_quatf(angle: Float(yaw) * radians, axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: -Float(pitch) * radians, axis: SIMD3(0, 0, 1))
            * simd_quatf(angle: Float(roll) * radians, axis: SIMD3(1, 0, 0))
    }
    private func corners() -> [SIMD3<Float>] {
        let b = plane.boundingBox
        return [b.min.x, b.max.x].flatMap { x in [b.min.y, b.max.y].flatMap { y in
            [b.min.z, b.max.z].map { z in SIMD3(Float(x), Float(y), Float(z)) }
        } }
    }
    private func addLight(position: SCNVector3, intensity: CGFloat, color: NSColor) {
        let node = SCNNode()
        node.light = SCNLight()
        node.light?.type = .directional
        node.light?.intensity = intensity
        node.light?.color = color
        node.position = position
        node.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(node)
    }

    private static func studioEnvironment() -> NSImage {
        let image = NSImage(size: NSSize(width: 512, height: 256))
        image.lockFocus()
        NSColor(white: 0.15, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 512, height: 256)).fill()
        NSGradient(starting: NSColor(white: 0.2, alpha: 1), ending: NSColor(white: 0.7, alpha: 1))!
            .draw(in: NSRect(x: 0, y: 100, width: 512, height: 156), angle: 90)
        NSColor(white: 0.98, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 75, y: 145, width: 185, height: 26), xRadius: 10, yRadius: 10).fill()
        NSBezierPath(roundedRect: NSRect(x: 370, y: 120, width: 65, height: 80), xRadius: 12, yRadius: 12).fill()
        image.unlockFocus()
        return image
    }
}
