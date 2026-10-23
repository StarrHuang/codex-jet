import AppKit
import SceneKit
import ResetCore
import simd

@main struct Flight3DTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: "/tmp/roadster-3d-proof")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let renderer = PaperPlane3DRenderer()
        let size = CGSize(width: 600, height: 420)
        func save(_ frame: PaperPlane3DRenderer.Frame, _ name: String) throws {
            let rep = NSBitmapImageRep(cgImage: frame.image)
            try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        let low = renderer.frame(size: size, lift: 0, speed: 0, phase: 0, launch: nil)
        try save(low, "01-ground")
        let high = renderer.frame(size: size, lift: 1, speed: 0, phase: 0, launch: nil)
        try save(high, "02-full")
        precondition(high.planeBounds.midY < low.planeBounds.midY - 100, "quota must raise actual projected geometry")
        let count = renderer.renderCount
        _ = renderer.frame(size: size, lift: 1, speed: 0, phase: 100, launch: nil)
        precondition(renderer.renderCount == count, "idle snapshot must reuse its cached render")
        let down = SIMD3<Float>(0, -1, 0)
        let inverted = PaperPlane3DRenderer.orientation(pitch: 0, roll: 180, yaw: 0)
        precondition(simd_distance(inverted.act(down), SIMD3(0, 1, 0)) < 0.001,
                     "paper normal follows the banked orientation")
        let sideways = PaperPlane3DRenderer.orientation(pitch: 0, roll: 90, yaw: 0)
        precondition(abs(sideways.act(down).z) > 0.99, "roll must be around paper longitudinal axis")
        let tilt = PaperPlane3DRenderer.orientation(pitch: 20, roll: 0, yaw: 0)
        precondition(tilt.act(SIMD3(-1, 0, 0)).y > 0.3, "takeoff pitch must raise the nose")
        var unique = Set<Data>()
        for (i, t) in [0.22, 0.43, 0.58, 0.73, 0.91].enumerated() {
            let pose = PaperPlaneLaunchPose(progress: t, bank: true)
            let frame = renderer.frame(size: size, lift: 0.2 + 0.7 * pose.liftProgress,
                                       speed: 0.6, phase: t * 12, launch: pose)
            try save(frame, "pose-\(i)")
            unique.insert(NSBitmapImageRep(cgImage: frame.image).representation(using: .png, properties: [:])!)
            precondition(frame.planeBounds.minY > 0 && frame.planeBounds.maxY < size.height * 0.95,
                         "maneuver must stay on screen and clear the floor")
        }
        precondition(unique.count == 5, "separate 3D poses must render different projections")
        let start = CFAbsoluteTimeGetCurrent()
        for i in 0..<24 {
            _ = renderer.frame(size: CGSize(width: 260, height: 185), lift: 0.6, speed: 0.5,
                               phase: Double(i) * 0.2, launch: nil)
        }
        print(String(format: "PASS: true mesh projection, folded paper orientation, altitude, finite poses, idle cache; frame average %.1f ms", (CFAbsoluteTimeGetCurrent() - start) / 24 * 1000))
        print(output.path)
    }
}
