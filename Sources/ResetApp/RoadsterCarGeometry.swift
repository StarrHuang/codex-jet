import SceneKit

/// Original procedural body. Front is -X, wheel contact is Y=0.
@MainActor
enum RoadsterCarGeometry {
    static func make() -> SCNNode {
        let car = SCNNode()
        car.name = "roadster"
        let pearl = material(NSColor(calibratedWhite: 0.79, alpha: 1), 0.32, 0.30)
        let glass = material(NSColor(calibratedRed: 0.075, green: 0.055, blue: 0.049, alpha: 1), 0.45, 0.16)
        let black = material(NSColor(calibratedWhite: 0.022, alpha: 1), 0.25, 0.40)
        let rubber = material(NSColor(calibratedWhite: 0.018, alpha: 1), 0, 0.85)
        let metal = material(NSColor(calibratedWhite: 0.48, alpha: 1), 0.88, 0.24)
        let led = material(NSColor.white, 0.15, 0.2)
        led.emission.contents = NSColor(calibratedWhite: 0.8, alpha: 1)
        let red = material(NSColor.systemRed, 0.2, 0.2)
        red.emission.contents = NSColor(calibratedRed: 0.85, green: 0.005, blue: 0.01, alpha: 1)
        addBody(to: car, paint: pearl, black: black)
        addCanopy(to: car, glass: glass, paint: pearl, black: black)
        addDetails(to: car, paint: pearl, black: black, metal: metal, led: led, red: red)
        addWheels(to: car, rubber: rubber, black: black, metal: metal)
        return car
    }

    private static func material(_ color: NSColor, _ metal: CGFloat, _ rough: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.metalness.contents = metal
        m.roughness.contents = rough
        m.lightingModel = .physicallyBased
        m.isDoubleSided = true
        return m
    }

    // Body stations retain the wide, squared nose and almost full-width rear deck.
    private static let outline: [(x: CGFloat, w: CGFloat, y: CGFloat)] = [
        (-2.22, 0.79, 0.52), (-2.12, 0.86, 0.57), (-1.85, 0.92, 0.65),
        (-1.42, 0.96, 0.70), (-0.95, 0.95, 0.72), (-0.50, 0.94, 0.70),
        (0.40, 0.94, 0.70), (1.10, 0.97, 0.73), (1.55, 0.96, 0.76),
        (1.95, 0.91, 0.73), (2.22, 0.86, 0.69)
    ]
    private static func bodyAt(_ x: CGFloat) -> (w: CGFloat, y: CGFloat) {
        for i in 0..<(outline.count - 1) where x <= outline[i + 1].x {
            let a = outline[i], b = outline[i + 1]
            let t = (x - a.x) / (b.x - a.x)
            return (a.w + (b.w - a.w) * t, a.y + (b.y - a.y) * t)
        }
        return (outline.last!.w, outline.last!.y)
    }
    private static func archBottom(_ x: CGFloat) -> CGFloat {
        var y: CGFloat = 0.205
        for center: CGFloat in [-1.34, 1.30] {
            let d = abs(x - center)
            if d < 0.395 { y = max(y, 0.355 + sqrt(0.395 * 0.395 - d * d)) }
        }
        return y
    }
    private static func addBody(to car: SCNNode, paint: SCNMaterial, black: SCNMaterial) {
        let xs = (0...180).map { -2.22 + CGFloat($0) * 4.44 / 180 }
        // Each upper row spans the hood, then swells upward into the front and rear fenders.
        let fractions: [CGFloat] = [-1, -0.94, -0.78, -0.55, 0, 0.55, 0.78, 0.94, 1]
        var top: [SCNVector3] = []
        for x in xs {
            let s = bodyAt(x)
            let wheelRise = max(exp(-pow((x + 1.34) / 0.43, 2)), exp(-pow((x - 1.30) / 0.45, 2)))
            for f in fractions {
                let shoulder = max(0, (abs(f) - 0.55) / 0.45)
                let y = s.y + 0.105 * wheelRise * shoulder - 0.025 * abs(f)
                top.append(SCNVector3(x, y, s.w * f))
            }
        }
        addMesh("continuous-hood-and-fenders", top, rows: xs.count, columns: fractions.count, to: car, material: paint)
        for side: CGFloat in [-1, 1] {
            var panel: [SCNVector3] = []
            var well: [SCNVector3] = []
            for x in xs {
                let s = bodyAt(x)
                let rise = max(exp(-pow((x + 1.34) / 0.43, 2)), exp(-pow((x - 1.30) / 0.45, 2)))
                let high = s.y + 0.105 * rise - 0.025
                let low = archBottom(x)
                // The lower edge is the actual wheel opening, never a rail floating outside the body.
                panel += [SCNVector3(x, high, side * s.w), SCNVector3(x, max(low, high - 0.12), side * (s.w + 0.006)), SCNVector3(x, max(low, 0.34), side * (s.w - 0.055)), SCNVector3(x, low, side * (s.w - 0.025))]
                well += [SCNVector3(x, low, side * (s.w - 0.025)), SCNVector3(x, low, side * 0.69)]
            }
            addMesh("sculpted-side-with-wheel-openings", panel, rows: xs.count, columns: 4, to: car, material: paint, flip: side < 0)
            addMesh("wheel-opening-inner-return", well, rows: xs.count, columns: 2, to: car, material: black)
            car.addChildNode(box(name: "carbon-door-sill", size: SCNVector3(1.77, 0.06, 0.08), position: SCNVector3(0, 0.203, side * 0.91), material: black))
        }
        for x: CGFloat in [-2.22, 2.22] {
            let s = bodyAt(x)
            let v = [SCNVector3(x, s.y, -s.w), SCNVector3(x, s.y, s.w), SCNVector3(x, 0.20, -s.w * 0.96), SCNVector3(x, 0.20, s.w * 0.96)]
            addMesh("closed-bumper", v, rows: 2, columns: 2, to: car, material: paint, flip: x < 0)
        }
        car.addChildNode(box(name: "sealed-carbon-undertray", size: SCNVector3(4.38, 0.055, 1.40), position: SCNVector3(0.03, 0.18, 0), material: black))
    }

    private static func addCanopy(to car: SCNNode, glass: SCNMaterial, paint: SCNMaterial, black: SCNMaterial) {
        // Wide rounded roof cross-sections: a crown, two roof shoulders, and steep side glass.
        // No center ridge. The window belt sits directly on the painted body.
        let sections: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (-1.08, 0.725, 0.74, 0.725), (-0.91, 0.84, 0.72, 0.72),
            (-0.65, 1.005, 0.70, 0.715), (-0.39, 1.115, 0.68, 0.71),
            (-0.12, 1.155, 0.68, 0.71), (0.22, 1.16, 0.69, 0.71),
            (0.50, 1.13, 0.70, 0.715), (0.76, 1.04, 0.71, 0.72),
            (1.02, 0.90, 0.72, 0.73), (1.26, 0.755, 0.71, 0.745)
        ]
        var vertices: [SCNVector3] = []
        for (x, roof, w, belt) in sections {
            vertices += [SCNVector3(x, belt, -w), SCNVector3(x, roof - (roof - belt) * 0.15, -w * 0.82), SCNVector3(x, roof - 0.012, -w * 0.57), SCNVector3(x, roof, 0), SCNVector3(x, roof - 0.012, w * 0.57), SCNVector3(x, roof - (roof - belt) * 0.15, w * 0.82), SCNVector3(x, belt, w)]
        }
        addMesh("curved-panoramic-glass", vertices, rows: sections.count, columns: 7, to: car, material: glass)
        for side: CGFloat in [-1, 1] {
            // A-pillars and rear buttresses follow the glass edge and are integrated with its beltline.
            for i in 0..<(sections.count - 1) {
                let a = sections[i], b = sections[i + 1]
                let pa = SCNVector3(a.0, a.1 - (a.1 - a.3) * 0.15, side * a.2 * 0.82)
                let pb = SCNVector3(b.0, b.1 - (b.1 - b.3) * 0.15, side * b.2 * 0.82)
                car.addChildNode(beam(from: pa, to: pb, thickness: 0.022, material: paint))
                car.addChildNode(beam(from: SCNVector3(a.0, a.3 + 0.002, side * a.2), to: SCNVector3(b.0, b.3 + 0.002, side * b.2), thickness: 0.014, material: paint))
            }
            car.addChildNode(beam(from: SCNVector3(0.12, 0.715, side * 0.695), to: SCNVector3(0.03, 1.145, side * 0.57), thickness: 0.012, material: black))
            // Rear white sail closes the window into the broad deck.
            let sail = [SCNVector3(0.55, 1.10, side * 0.58), SCNVector3(1.30, 0.75, side * 0.70), SCNVector3(0.80, 0.72, side * 0.78)]
            let node = SCNNode(geometry: geometry(vertices: sail, triangles: [0,1,2], material: paint, smooth: false))
            node.name = "rear-quarter-buttress"; car.addChildNode(node)
        }
    }

    private static func addDetails(to car: SCNNode, paint: SCNMaterial, black: SCNMaterial, metal: SCNMaterial, led: SCNMaterial, red: SCNMaterial) {
        let fascia = [SCNVector3(-2.244,0.505,-0.68), SCNVector3(-2.244,0.505,0.68), SCNVector3(-2.244,0.265,-0.73), SCNVector3(-2.244,0.265,0.73)]
        addMesh("tapered-front-fascia", fascia, rows:2,columns:2,to:car,material:black,flip:true)
        car.addChildNode(box(name: "front-light-blade", size: SCNVector3(0.042, 0.012, 1.37), position: SCNVector3(-2.25, 0.51, 0), material: led))
        car.addChildNode(box(name: "front-splitter", size: SCNVector3(0.30, 0.04, 1.74), position: SCNVector3(-2.11, 0.19, 0), material: black))
        for side: CGFloat in [-1, 1] {
            let corners: [(CGFloat,CGFloat)] = [(-2.165,0.675),(-1.91,0.835),(-1.96,0.635)]
            let lamp = corners.map { x,z -> SCNVector3 in
                let section = bodyAt(x)
                let fraction = z / section.w
                let rise = exp(-pow((x + 1.34) / 0.43, 2))
                let y = section.y + 0.105 * rise * max(0,(fraction - 0.55)/0.45) - 0.025*fraction + 0.008
                return SCNVector3(x,y,side*z)
            }
            let bezel = SCNNode(geometry: geometry(vertices: lamp, triangles:[0,1,2],material:black,smooth:false))
            bezel.name = "triangular-headlamp-bezel"; car.addChildNode(bezel)
            let center = SCNVector3((lamp[0].x+lamp[1].x+lamp[2].x)/3,(lamp[0].y+lamp[1].y+lamp[2].y)/3,(lamp[0].z+lamp[1].z+lamp[2].z)/3)
            let inner = lamp.map { SCNVector3(center.x+($0.x-center.x)*0.83, center.y+($0.y-center.y)*0.83+0.002, center.z+($0.z-center.z)*0.83) }
            let node = SCNNode(geometry: geometry(vertices: inner, triangles:[0,1,2],material:led,smooth:false))
            node.name = "triangular-headlamp"; car.addChildNode(node)
            car.addChildNode(beam(from: SCNVector3(-1.94,0.662,side*0.63), to: SCNVector3(-1.05,0.731,side*0.70), thickness: 0.006, material: black))
            car.addChildNode(beam(from: SCNVector3(0.62,0.69,side*0.945), to: SCNVector3(0.53,0.25,side*0.918), thickness: 0.006, material: black))
            car.addChildNode(box(name: "flush-door-handle", size: SCNVector3(0.16,0.016,0.012), position: SCNVector3(0.32,0.66,side*0.947), material: black))
        }
        car.addChildNode(box(name: "rear-light-recess", size: SCNVector3(0.04,0.12,1.69), position: SCNVector3(2.242,0.645,0), material: black))
        car.addChildNode(box(name: "full-width-red-tail-light", size: SCNVector3(0.045,0.025,1.65), position: SCNVector3(2.266,0.656,0), material: red))
        car.addChildNode(box(name: "rear-valance", size: SCNVector3(0.07,0.24,1.67), position: SCNVector3(2.21,0.33,0), material: black))
        car.addChildNode(box(name: "rear-diffuser", size: SCNVector3(0.45,0.045,1.75), position: SCNVector3(2.02,0.175,0), material: black))
        for z: CGFloat in [-0.72,-0.36,0,0.36,0.72] {
            car.addChildNode(box(name: "diffuser-fin", size: SCNVector3(0.43,0.14,0.025), position: SCNVector3(2.01,0.245,z), material: black))
        }
        car.addChildNode(beam(from: SCNVector3(2.20,0.717,-0.86), to: SCNVector3(2.20,0.717,0.86), thickness: 0.018, material: black))
        _ = paint; _ = metal
    }

    private static func addWheels(to car: SCNNode, rubber: SCNMaterial, black: SCNMaterial, metal: SCNMaterial) {
        for x: CGFloat in [-1.34, 1.30] {
            for side: CGFloat in [-1, 1] {
                let wheel = SCNNode(); wheel.position = SCNVector3(x,0.355,side*0.825)
                wheel.name = x < 0 ? "front-wheel" : "rear-wheel"; car.addChildNode(wheel)
                let tire = cylinder(name: "tire", radius: 0.355, height: 0.235, position: SCNVector3Zero, material: rubber)
                tire.eulerAngles.x = .pi/2; wheel.addChildNode(tire)
                let disc = cylinder(name: "brake-disc", radius: 0.248, height: 0.025, position: SCNVector3(0,0,side*0.115), material: black)
                disc.eulerAngles.x = .pi/2; wheel.addChildNode(disc)
                let rim = torus(name: "polished-wheel-rim", ring: 0.277, pipe: 0.014, position: SCNVector3(0,0,side*0.126), material: metal)
                rim.eulerAngles.x = .pi/2; wheel.addChildNode(rim)
                // Five paired swept spokes, modeled as solid metal blades.
                for j in 0..<10 {
                    let angle = CGFloat(j/2) * .pi*2/5 + (j%2 == 0 ? -0.045 : 0.10)
                    let blade = [SCNVector3(cos(angle-0.15)*0.060,sin(angle-0.15)*0.060,side*0.135), SCNVector3(cos(angle+0.03)*0.273,sin(angle+0.03)*0.273,side*0.135), SCNVector3(cos(angle+0.20)*0.265,sin(angle+0.20)*0.265,side*0.135), SCNVector3(cos(angle+0.20)*0.070,sin(angle+0.20)*0.070,side*0.135)]
                    let node = SCNNode(geometry:geometry(vertices:blade,triangles:[0,1,2,0,2,3],material:metal,smooth:false))
                    node.name = "forged-blade-spoke"; wheel.addChildNode(node)
                }
                let hub = cylinder(name:"wheel-hub",radius:0.057,height:0.025,position:SCNVector3(0,0,side*0.143),material:metal)
                hub.eulerAngles.x = .pi/2; wheel.addChildNode(hub)
            }
        }
    }

    private static func addMesh(_ name: String, _ vertices: [SCNVector3], rows: Int, columns: Int, to car: SCNNode, material: SCNMaterial, flip: Bool = false) {
        var indices: [UInt32] = []
        for row in 0..<(rows-1) {
            for column in 0..<(columns-1) {
                let a = UInt32(row*columns+column), b = a+1, c = a+UInt32(columns), d = c+1
                indices += flip ? [a,c,b,b,c,d] : [a,b,c,b,d,c]
            }
        }
        let node = SCNNode(geometry: geometry(vertices:vertices,triangles:indices,material:material,smooth:true))
        node.name = name; car.addChildNode(node)
    }

    private static func box(name: String, size: SCNVector3, position: SCNVector3,
                            material: SCNMaterial) -> SCNNode {
        let shape = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: 0)
        shape.materials = [material]
        let node = SCNNode(geometry: shape)
        node.name = name
        node.position = position
        return node
    }

    private static func cylinder(name: String, radius: CGFloat, height: CGFloat,
                                 position: SCNVector3, material: SCNMaterial) -> SCNNode {
        let shape = SCNCylinder(radius: radius, height: height)
        shape.radialSegmentCount = 32
        shape.materials = [material]
        let node = SCNNode(geometry: shape)
        node.name = name
        node.position = position
        return node
    }

    private static func torus(name: String, ring: CGFloat, pipe: CGFloat,
                               position: SCNVector3, material: SCNMaterial) -> SCNNode {
        let shape = SCNTorus(ringRadius: ring, pipeRadius: pipe)
        shape.ringSegmentCount = 48
        shape.pipeSegmentCount = 12
        shape.materials = [material]
        let node = SCNNode(geometry: shape)
        node.name = name
        node.position = position
        return node
    }

    private static func beam(from start: SCNVector3, to end: SCNVector3,
                             thickness: CGFloat, material: SCNMaterial) -> SCNNode {
        let delta = SCNVector3(end.x - start.x, end.y - start.y, end.z - start.z)
        let length = sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)
        let geometry = SCNCylinder(radius: thickness / 2, height: CGFloat(length))
        geometry.radialSegmentCount = 8
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3((start.x + end.x) / 2, (start.y + end.y) / 2, (start.z + end.z) / 2)
        let direction = SCNVector3(delta.x / length, delta.y / length, delta.z / length)
        let crossX = direction.z
        let crossZ = -direction.x
        let quaternionLength = sqrt(crossX * crossX + crossZ * crossZ + (1 + direction.y) * (1 + direction.y))
        node.orientation = SCNQuaternion(crossX / quaternionLength, 0, crossZ / quaternionLength,
                                         (1 + direction.y) / quaternionLength)
        node.name = "structural-beam"
        return node
    }

    private static func geometry(vertices: [SCNVector3], triangles: [UInt32],
                                 material: SCNMaterial, smooth: Bool) -> SCNGeometry {
        // SCNVector3 uses CGFloat storage on macOS; the geometry source below is
        // explicitly Float-based, so pack components instead of copying the structs.
        let packedVertices = vertices.flatMap { [Float($0.x), Float($0.y), Float($0.z)] }
        let vertexData = packedVertices.withUnsafeBufferPointer { Data(buffer: $0) }
        let source = SCNGeometrySource(data: vertexData, semantic: .vertex, vectorCount: vertices.count,
                                       usesFloatComponents: true, componentsPerVector: 3,
                                       bytesPerComponent: MemoryLayout<Float>.size,
                                       dataOffset: 0, dataStride: MemoryLayout<Float>.size * 3)
        let indexData = triangles.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(data: indexData, primitiveType: .triangles,
                                         primitiveCount: triangles.count / 3, bytesPerIndex: MemoryLayout<UInt32>.size)
        var sources = [source]
        if smooth {
            var normals = Array(repeating: SCNVector3Zero, count: vertices.count)
            for offset in stride(from: 0, to: triangles.count, by: 3) {
                let ia = Int(triangles[offset]), ib = Int(triangles[offset + 1]), ic = Int(triangles[offset + 2])
                let a = vertices[ia], b = vertices[ib], c = vertices[ic]
                let ab = SCNVector3(b.x - a.x, b.y - a.y, b.z - a.z)
                let ac = SCNVector3(c.x - a.x, c.y - a.y, c.z - a.z)
                let normal = SCNVector3(ab.y * ac.z - ab.z * ac.y,
                                        ab.z * ac.x - ab.x * ac.z,
                                        ab.x * ac.y - ab.y * ac.x)
                for index in [ia, ib, ic] {
                    normals[index].x += normal.x
                    normals[index].y += normal.y
                    normals[index].z += normal.z
                }
            }
            for index in normals.indices {
                let length = sqrt(normals[index].x * normals[index].x + normals[index].y * normals[index].y + normals[index].z * normals[index].z)
                if length > 0 {
                    normals[index] = SCNVector3(normals[index].x / length, normals[index].y / length, normals[index].z / length)
                }
            }
            let packedNormals = normals.flatMap { [Float($0.x), Float($0.y), Float($0.z)] }
            let normalData = packedNormals.withUnsafeBufferPointer { Data(buffer: $0) }
            sources.append(SCNGeometrySource(data: normalData, semantic: .normal, vectorCount: normals.count,
                                             usesFloatComponents: true, componentsPerVector: 3,
                                             bytesPerComponent: MemoryLayout<Float>.size,
                                             dataOffset: 0, dataStride: MemoryLayout<Float>.size * 3))
        }
        let mesh = SCNGeometry(sources: sources, elements: [element])
        mesh.materials = [material]
        return mesh
    }
}
