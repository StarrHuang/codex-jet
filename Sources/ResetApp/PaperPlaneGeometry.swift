import SceneKit
import simd

/// Folded paper dart. The nose points down -X; wings span Z and Y is up.
@MainActor
enum PaperPlaneGeometry {
    static func make() -> SCNNode {
        let plane = SCNNode()
        plane.name = "paper-plane"
        let paper = material(NSColor(calibratedRed: 0.88, green: 0.90, blue: 0.92, alpha: 1))
        let foldedPaper = material(NSColor(calibratedRed: 0.80, green: 0.83, blue: 0.86, alpha: 1))
        let underside = material(NSColor(calibratedRed: 0.72, green: 0.71, blue: 0.68, alpha: 1))
        underside.emission.contents = NSColor(calibratedRed: 0.085, green: 0.080, blue: 0.070, alpha: 1)
        let cutEdge = material(NSColor(calibratedRed: 0.66, green: 0.67, blue: 0.68, alpha: 1))
        let crease = material(NSColor(calibratedRed: 0.51, green: 0.55, blue: 0.59, alpha: 1))
        crease.transparency = 0.24
        let nose = SIMD3<Float>(-2.10, 0.0, 0)
        let keel = SIMD3<Float>(1.65, -0.25, 0)
        for side: Float in [-1, 1] {
            let tip = SIMD3<Float>(2.10, 0.10, side * 1.40)
            let shoulder = SIMD3<Float>(1.75, 0.078, side * 0.88)
            let root = SIMD3<Float>(1.30, 0.046, side * 0.22)
            // The two slightly different wing planes give the long fold a quiet highlight.
            addPanel([nose, tip, shoulder], name: "outer-wing-fold", top: paper,
                     bottom: underside, edge: cutEdge, to: plane)
            addPanel([nose, shoulder, root], name: "inner-wing-fold", top: paper,
                     bottom: underside, edge: cutEdge, to: plane)
            // These deep triangular panels are the folded center body, not a flat decal.
            addPanel([nose, root, keel], name: "folded-center-keel", top: foldedPaper,
                     bottom: underside, edge: cutEdge, to: plane)
            addCrease(from: nose + SIMD3(0, 0.004, 0), to: root + SIMD3(0, 0.004, 0),
                      material: crease, to: plane)
            addCrease(from: nose + SIMD3(0, 0.004, 0), to: shoulder + SIMD3(0, 0.004, 0),
                      material: crease, to: plane)
        }
        return plane
    }

    private static func material(_ color: NSColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = 0.0
        m.roughness.contents = 0.82
        m.specular.contents = NSColor(calibratedWhite: 0.12, alpha: 1)
        m.isDoubleSided = false
        return m
    }

    private static func addPanel(_ corners: [SIMD3<Float>], name: String,
                                 top: SCNMaterial, bottom: SCNMaterial, edge: SCNMaterial,
                                 to plane: SCNNode) {
        var p = corners
        if simd_cross(p[1] - p[0], p[2] - p[0]).y < 0 { p.swapAt(1, 2) }
        let normal = simd_normalize(simd_cross(p[1] - p[0], p[2] - p[0]))
        let halfThickness: Float = 0.003
        let upper = p.map { $0 + normal * halfThickness }
        let lower = p.map { $0 - normal * halfThickness }
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var elements: [SCNGeometryElement] = []
        // Separate normal domains retain crisp paper edges and a shaded reverse face.
        let groups: [[[SIMD3<Float>]]] = [
            [[upper[0], upper[1], upper[2]]],
            [[lower[0], lower[2], lower[1]]],
            (0..<3).flatMap { i -> [[SIMD3<Float>]] in
                let j = (i + 1) % 3
                return [[upper[i], lower[i], upper[j]], [upper[j], lower[i], lower[j]]]
            }
        ]
        for triangles in groups {
            var indices: [UInt32] = []
            for triangle in triangles {
                let n = simd_normalize(simd_cross(triangle[1] - triangle[0], triangle[2] - triangle[0]))
                for v in triangle {
                    indices.append(UInt32(vertices.count))
                    vertices.append(SCNVector3(v))
                    normals.append(SCNVector3(n))
                }
            }
            elements.append(SCNGeometryElement(indices: indices, primitiveType: .triangles))
        }
        let mesh = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)], elements: elements)
        mesh.materials = [top, bottom, edge]
        let node = SCNNode(geometry: mesh)
        node.name = name
        plane.addChildNode(node)
    }

    private static func addCrease(from a: SIMD3<Float>, to b: SIMD3<Float>,
                                  material: SCNMaterial, to plane: SCNNode) {
        let line = SCNCylinder(radius: 0.0018, height: CGFloat(simd_length(b - a)))
        line.radialSegmentCount = 5
        line.materials = [material]
        let node = SCNNode(geometry: line)
        node.name = "paper-fold-crease"
        node.simdPosition = (a + b) / 2
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(b - a))
        plane.addChildNode(node)
    }
}
