import AppKit
import Metal
import SceneKit
import ResetCore
import simd

/// A persistent, depth-tested scene. Every frame projects the mesh, including its underside;
/// the canvas only composites that render beside the unchanged capacity bottle.
@MainActor final class Roadster3DRenderer: ObservableObject {
    struct Frame {
        let image: CGImage
        let carBounds: CGRect
    }
    private struct Key: Equatable {
        let size: CGSize
        let lift: Double
        let speed: Double
        let phase: Double
        let launch: RoadsterLaunchPose?
    }
    let scene = SCNScene()
    let vehicle = SCNNode()
    let car = RoadsterCarGeometry.make()
    private let renderer: SCNRenderer
    private let camera = SCNNode()
    private var jets: [(node: SCNNode, mist: [SCNNode], rear: Bool)] = []
    private var bodyBounds = (min: SCNVector3Zero, max: SCNVector3Zero)
    private var cached: (Key, Frame)?
    private(set) var renderCount = 0

    init() {
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Roadster 3D requires Metal") }
        renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        scene.background.contents = NSColor.clear
        scene.lightingEnvironment.contents = Self.studioEnvironment()
        scene.lightingEnvironment.intensity = 0.45
        let lens = SCNCamera()
        lens.usesOrthographicProjection = true
        lens.orthographicScale = 2.85
        lens.zNear = 0.1
        lens.zFar = 60
        lens.wantsHDR = true
        lens.exposureOffset = -0.65
        lens.wantsExposureAdaptation = false
        lens.bloomIntensity = 0.08
        lens.bloomThreshold = 1.2
        camera.camera = lens
        camera.position = SCNVector3(-6.4, 7.0, 10)
        camera.look(at: SCNVector3(0, 1.80, 0))
        scene.rootNode.addChildNode(camera)
        renderer.pointOfView = camera
        addLight(position: SCNVector3(-3, 7, 5), intensity: 700, color: .white)
        addLight(position: SCNVector3(4, 4, -5), intensity: 800,
                 color: NSColor(red: 0.72, green: 0.84, blue: 1, alpha: 1))
        addLight(position: SCNVector3(-3, 2, -3), intensity: 250,
                 color: NSColor(red: 1, green: 0.84, blue: 0.66, alpha: 1))
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 90
        ambient.light?.color = NSColor(white: 0.8, alpha: 1)
        scene.rootNode.addChildNode(ambient)
        bodyBounds = car.boundingBox
        car.position.y = -0.58
        vehicle.addChildNode(car)
        scene.rootNode.addChildNode(vehicle)
        // Outlets are anchored to the chassis. The rear exhaust points +X; lift jets point -Y.
        for z: Float in [-0.63, -0.21, 0.21, 0.63] {
            addJet(at: SIMD3(2.24, 0.34, z), rear: true)
        }
        for x: Float in [-1.25, 1.25] {
            for z: Float in [-0.62, 0.62] { addJet(at: SIMD3(x, 0.15, z), rear: false) }
        }
    }

    func frame(size: CGSize, lift: Double, speed: Double, phase: Double,
               launch: RoadsterLaunchPose?) -> Frame {
        let key = Key(size: size, lift: lift, speed: speed, phase: speed > 0 || launch != nil ? phase : 0, launch: launch)
        if let cached, cached.0 == key { return cached.1 }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        let pitch = launch?.pitchDegrees ?? 0
        let roll = launch?.rollDegrees ?? 0
        let yaw = launch?.yawDegrees ?? 0
        vehicle.simdOrientation = Self.orientation(pitch: pitch, roll: roll, yaw: yaw)
        vehicle.simdPosition = SIMD3(Float(-speed * 0.10), Float(0.58 + lift * 2.35), 0)
        // Keep real vertices above the pad during the finite refill maneuver.
        if launch != nil {
            let minimum = corners().map { vehicle.simdConvertPosition($0, to: nil).y }.min()!
            if minimum < 0.015 { vehicle.position.y += CGFloat(0.015 - minimum) }
        }
        for (index, jet) in jets.enumerated() {
            let launchThrust = launch?.thrust ?? 0
            let strength = jet.rear ? min(1, speed * 0.60 + launchThrust * 0.36)
                : launchThrust * (index.isMultiple(of: 2) ? 1 : 0.72)
            jet.node.isHidden = strength <= 0.01
            let length = Float(0.20 + strength * (jet.rear ? 1.45 : 0.92))
            let gasPhase = (phase + (launch?.liftProgress ?? 0) * 25) / (2 * Double.pi) * 1.6
            for (i, puff) in jet.mist.enumerated() {
                let t = Float((gasPhase + Double(i) / 12 + Double(index) * 0.13)
                    .truncatingRemainder(dividingBy: 1))
                let radius = 0.03 + t * 0.16
                puff.simdPosition = SIMD3(sin(t * 9 + Float(index)) * t * 0.04,
                    -0.07 - t * length, cos(t * 7 + Float(index)) * t * 0.03)
                puff.simdScale = SIMD3(radius * 2, radius * 2, radius * 2)
                puff.opacity = Double(pow(1 - t, 1.2)) * strength * 0.45
            }
        }
        SCNTransaction.commit()
        let pixels = CGSize(width: ceil(size.width * 2), height: ceil(size.height * 2))
        let snapshot = renderer.snapshot(atTime: 0, with: pixels, antialiasingMode: .multisampling4X)
        var rect = CGRect(origin: .zero, size: pixels)
        guard let image = snapshot.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            fatalError("SceneKit Roadster snapshot has no pixel image")
        }
        let projected = corners().map { corner -> CGPoint in
            let p = renderer.projectPoint(vehicle.convertPosition(SCNVector3(corner), to: nil))
            return CGPoint(x: CGFloat(p.x) / 2, y: size.height - CGFloat(p.y) / 2)
        }
        let bounds = CGRect(x: projected.map(\.x).min()!, y: projected.map(\.y).min()!,
            width: projected.map(\.x).max()! - projected.map(\.x).min()!,
            height: projected.map(\.y).max()! - projected.map(\.y).min()!)
        let frame = Frame(image: image, carBounds: bounds)
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
        let b = bodyBounds
        return [b.min.x, b.max.x].flatMap { x in
            [b.min.y, b.max.y].flatMap { y in
                [b.min.z, b.max.z].map { z in SIMD3(Float(x), Float(y) - 0.58, Float(z)) }
            }
        }
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

    private func addJet(at position: SIMD3<Float>, rear: Bool) {
        let mount = SCNNode()
        mount.name = rear ? "rear-exhaust" : "lift-exhaust"
        mount.simdPosition = position
        if rear { mount.simdOrientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1)) }
        car.addChildNode(mount)
        let metal = SCNMaterial()
        metal.lightingModel = .physicallyBased
        metal.diffuse.contents = NSColor(red: 0.43, green: 0.34, blue: 0.23, alpha: 1)
        metal.metalness.contents = 0.86
        metal.roughness.contents = 0.28
        let ring = SCNTube(innerRadius: 0.055, outerRadius: 0.069, height: 0.115)
        ring.radialSegmentCount = 32
        ring.materials = [metal]
        let outlet = SCNNode(geometry: ring)
        outlet.position.y = -0.015
        mount.addChildNode(outlet)
        let plume = SCNNode()
        mount.addChildNode(plume)
        let vapor = SCNMaterial()
        vapor.lightingModel = .constant
        vapor.diffuse.contents = Self.vaporTexture
        vapor.blendMode = .alpha
        vapor.writesToDepthBuffer = false
        vapor.isDoubleSided = true
        var mist: [SCNNode] = []
        for _ in 0..<12 {
            let particle = SCNPlane(width: 1, height: 1)
            particle.materials = [vapor]
            let puff = SCNNode(geometry: particle)
            puff.constraints = [SCNBillboardConstraint()]
            plume.addChildNode(puff)
            mist.append(puff)
        }
        jets.append((plume, mist, rear))
    }

    private static let vaporTexture: NSImage = {
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: 64, height: 64)
        let gradient = NSGradient(colorsAndLocations:
            (NSColor(red: 0.91, green: 0.97, blue: 1, alpha: 0.90), 0),
            (NSColor(red: 0.80, green: 0.90, blue: 0.96, alpha: 0.28), 0.38),
            (NSColor(red: 0.72, green: 0.86, blue: 0.94, alpha: 0), 1))!
        gradient.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
        image.unlockFocus()
        return image
    }()

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
