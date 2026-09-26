import SceneKit
import SwiftUI
import UIKit
import simd

/// A spatial overview of the same millimetre coordinates used by the slice renderer.
/// SceneKit is y-up: LPS (x, y, z) becomes scene (x, z, -y).
struct VolumeSceneView: UIViewRepresentable {
  var subject: String
  var selectedAnchor: SIMD3<Float>
  var tiltDegrees: Double
  var sliceOffset: Double
  var visibleLayers: Set<TissueLayer>
  var onSelectAnchor: ((SIMD3<Float>) -> Void)? = nil
  var showsCutPlane: Bool = true
  var showsMarker: Bool = true

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> SCNView {
    let view = SCNView(frame: .zero)
    view.backgroundColor = .clear
    view.isOpaque = false
    view.antialiasingMode = .multisampling4X
    view.preferredFramesPerSecond = 30
    view.allowsCameraControl = true
    view.defaultCameraController.interactionMode = .orbitTurntable
    view.defaultCameraController.inertiaEnabled = !UIAccessibility.isReduceMotionEnabled
    view.defaultCameraController.target = SCNVector3(0, 288, 0)
    view.defaultCameraController.minimumVerticalAngle = -65
    view.defaultCameraController.maximumVerticalAngle = 65
    view.isAccessibilityElement = true
    view.accessibilityLabel = "Interactive three-dimensional volume"
    context.coordinator.install(in: view)
    context.coordinator.update(self)
    return view
  }

  func updateUIView(_ uiView: SCNView, context: Context) {
    context.coordinator.update(self)
  }

  @MainActor
  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    private var scene = SCNScene()
    private var subjectRoot = SCNNode()
    private var planeRoot = SCNNode()
    private var markerRoot = SCNNode()
    private var cameraNode = SCNNode()
    private var layerNodes: [TissueLayer: SCNNode] = [:]
    private var currentSubject = ""
    private var onSelectAnchor: ((SIMD3<Float>) -> Void)?
    private weak var view: SCNView?

    private let cyan = UIColor(red: 0.34, green: 0.87, blue: 1, alpha: 1)
    private let blue = UIColor(red: 0.16, green: 0.54, blue: 0.95, alpha: 1)
    private let coral = UIColor(red: 1, green: 0.40, blue: 0.34, alpha: 1)
    private let gold = UIColor(red: 1, green: 0.77, blue: 0.35, alpha: 1)

    func install(in view: SCNView) {
      self.view = view
      view.scene = scene
      scene.rootNode.addChildNode(subjectRoot)
      scene.rootNode.addChildNode(planeRoot)
      scene.rootNode.addChildNode(markerRoot)

      let camera = SCNCamera()
      camera.usesOrthographicProjection = true
      camera.orthographicScale = 350
      camera.zNear = 1
      camera.zFar = 4000
      camera.wantsHDR = true
      camera.bloomIntensity = 0.25
      camera.bloomThreshold = 0.8
      camera.bloomBlurRadius = 5
      cameraNode.camera = camera
      scene.rootNode.addChildNode(cameraNode)
      resetCamera()
      view.pointOfView = cameraNode

      addLight(type: .ambient, color: UIColor(red: 0.48, green: 0.66, blue: 0.86, alpha: 1), intensity: 440, position: SIMD3(0, 800, 500))
      addLight(type: .omni, color: UIColor(red: 0.60, green: 0.85, blue: 1, alpha: 1), intensity: 1050, position: SIMD3(-420, 750, 750))
      addLight(type: .omni, color: UIColor(red: 0.20, green: 0.58, blue: 1, alpha: 1), intensity: 800, position: SIMD3(350, 440, -500))
      addLight(type: .omni, color: UIColor(red: 1, green: 0.58, blue: 0.37, alpha: 1), intensity: 380, position: SIMD3(300, 80, 300))
      makeReferenceRings()
      makeCutPlane()
      makeMarker()

      let tap = UITapGestureRecognizer(target: self, action: #selector(selectStructure(_:)))
      tap.delegate = self
      view.addGestureRecognizer(tap)
      let reset = UITapGestureRecognizer(target: self, action: #selector(resetCamera))
      reset.numberOfTapsRequired = 2
      reset.delegate = self
      view.addGestureRecognizer(reset)
      tap.require(toFail: reset)
    }

    func update(_ value: VolumeSceneView) {
      onSelectAnchor = value.onSelectAnchor
      planeRoot.isHidden = !value.showsCutPlane
      markerRoot.isHidden = !value.showsMarker
      view?.accessibilityHint = value.onSelectAnchor == nil
        ? "Drag to rotate. Pinch to zoom. Double-tap to reset the view."
        : "Drag to rotate. Pinch to zoom. Tap a structure to place the cut. Double-tap to reset the view."
      if currentSubject != value.subject {
        currentSubject = value.subject
        subjectRoot.childNodes.forEach { $0.removeFromParentNode() }
        layerNodes.removeAll()
        switch value.subject {
        case "sun": makeSun()
        case "circuit": makeCircuit()
        default: makePatient()
        }
        resetCamera()
      }
      for (layer, node) in layerNodes {
        node.isHidden = !value.visibleLayers.contains(layer)
      }
      let plane = CutPlane.hinged(
        pivot: value.selectedAnchor,
        tiltDegrees: Float(value.tiltDegrees),
        offsetMM: Float(value.sliceOffset),
        fovMM: SIMD2(400, 400)
      )
      let u = Self.scenePoint(plane.u)
      let v = Self.scenePoint(plane.v)
      let n = Self.scenePoint(plane.n)
      let p = Self.scenePoint(plane.center)
      planeRoot.simdTransform = simd_float4x4(columns: (
        SIMD4(u, 0), SIMD4(v, 0), SIMD4(n, 0), SIMD4(p, 1)
      ))
      markerRoot.simdPosition = Self.scenePoint(value.selectedAnchor)
      view?.accessibilityValue = "\(value.subject.capitalized). Cut angle \(Int(value.tiltDegrees)) degrees. Anchor \(Int(value.selectedAnchor.x)), \(Int(value.selectedAnchor.y)), \(Int(value.selectedAnchor.z)) millimetres."
      view?.setNeedsDisplay()
    }

    @objc private func resetCamera() {
      cameraNode.camera?.orthographicScale = 350
      cameraNode.simdPosition = SIMD3(720, 440, 1150)
      cameraNode.look(at: SCNVector3(0, 288, 0))
      view?.pointOfView = cameraNode
      view?.defaultCameraController.target = SCNVector3(0, 288, 0)
    }

    @objc private func selectStructure(_ gesture: UITapGestureRecognizer) {
      guard let view, let onSelectAnchor else { return }
      let hits = view.hitTest(gesture.location(in: view), options: [
        .categoryBitMask: 1,
        .ignoreHiddenNodes: true,
        .searchMode: SCNHitTestSearchMode.closest.rawValue
      ])
      guard let result = hits.first else { return }
      let p = result.worldCoordinates
      let anchor = SIMD3<Float>(p.x, -p.z, p.y)
      guard PatientSpace.contains(anchor) else { return }
      onSelectAnchor(anchor)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

    private static func scenePoint(_ p: SIMD3<Float>) -> SIMD3<Float> { SIMD3(p.x, p.z, -p.y) }

    private func addLight(type: SCNLight.LightType, color: UIColor, intensity: CGFloat, position: SIMD3<Float>) {
      let node = SCNNode()
      let light = SCNLight()
      light.type = type
      light.color = color
      light.intensity = intensity
      node.light = light
      node.simdPosition = position
      scene.rootNode.addChildNode(node)
    }

    private func material(_ color: UIColor, opacity: CGFloat = 1, glow: CGFloat = 0, metallic: CGFloat = 0.1) -> SCNMaterial {
      let result = SCNMaterial()
      result.lightingModel = .physicallyBased
      result.diffuse.contents = color
      result.metalness.contents = metallic
      result.roughness.contents = 0.42
      result.emission.contents = color
      result.emission.intensity = glow
      result.transparency = opacity
      result.isDoubleSided = true
      if opacity < 1 {
        result.transparencyMode = .dualLayer
        result.writesToDepthBuffer = false
      }
      return result
    }

    private func lineMaterial(_ color: UIColor, opacity: CGFloat = 1) -> SCNMaterial {
      let result = SCNMaterial()
      result.lightingModel = .constant
      result.diffuse.contents = color
      result.emission.contents = color
      result.emission.intensity = 0.45
      result.transparency = opacity
      result.writesToDepthBuffer = false
      result.isDoubleSided = true
      return result
    }

    private func layerRoot(_ layer: TissueLayer) -> SCNNode {
      if let node = layerNodes[layer] { return node }
      let node = SCNNode()
      node.name = layer.rawValue
      subjectRoot.addChildNode(node)
      layerNodes[layer] = node
      return node
    }

    private func makePatient() {
      let bodyMaterial = material(blue, opacity: 0.045, glow: 0.22)
      let body = SCNNode(geometry: bodyEnvelope())
      body.geometry?.materials = [bodyMaterial]
      body.categoryBitMask = 2
      body.renderingOrder = 1
      layerRoot(.skin).addChildNode(body)

      // A few fine contours give the translucent envelope shape without hiding anatomy.
      for side: Float in [-1, 1] {
        let points: [SIMD3<Float>] = [
          SIMD3(side * 104, 0, 0), SIMD3(side * 148, 60, 0),
          SIMD3(side * 138, 180, 0), SIMD3(side * 148, 340, 0),
          SIMD3(side * 166, 460, 0), SIMD3(side * 150, 520, 0),
          SIMD3(side * 76, 574, 0)
        ]
        addTube(points, radius: 0.8, material: lineMaterial(cyan, opacity: 0.30), to: layerRoot(.skin), category: 2)
      }

      for primitive in PatientPhantom.primitives {
        guard let layer = primitive.label.layer else { continue }
        if [.skin, .fat, .muscle].contains(primitive.label) { continue }
        if primitive.label == .boneTrabecular || primitive.label == .spinalCanal { continue }
        let geometry: SCNGeometry
        switch primitive.kind {
        case .ellipsoid:
          let sphere = SCNSphere(radius: 1)
          sphere.segmentCount = primitive.label.isFinding ? 24 : 48
          geometry = sphere
        case .ellipticCylinder(let range, let thickness):
          if thickness != nil {
            makeRibs(primitive, range: range)
            continue
          }
          if primitive.label == .boneCortical && primitive.center.y > 30 {
            makeSpine(primitive, range: range)
            continue
          }
          let cylinder = SCNCylinder(radius: 1, height: CGFloat(range.upperBound - range.lowerBound))
          cylinder.radialSegmentCount = 32
          geometry = cylinder
        }
        let node = SCNNode(geometry: geometry)
        node.name = primitive.label.displayName
        node.simdPosition = Self.scenePoint(primitive.center)
        switch primitive.kind {
        case .ellipsoid:
          node.simdScale = SIMD3(primitive.halfAxes.x, primitive.halfAxes.z, primitive.halfAxes.y)
        case .ellipticCylinder:
          node.simdScale = SIMD3(primitive.halfAxes.x, 1, primitive.halfAxes.y)
        }
        node.geometry?.materials = [tissueMaterial(primitive.label)]
        node.renderingOrder = primitive.label.isFinding ? 8 : 3
        layerRoot(layer).addChildNode(node)
      }

      makeAirways()
      // Paired muscle strands and a faint inner envelope remain individually peelable.
      for x: Float in [-123, 123] {
        let strand = SCNNode(geometry: SCNCapsule(capRadius: 9, height: 365))
        strand.position = SCNVector3(x, 265, -46)
        strand.geometry?.materials = [material(UIColor(red: 0.75, green: 0.38, blue: 0.45, alpha: 1), opacity: 0.18)]
        strand.categoryBitMask = 2
        layerRoot(.muscle).addChildNode(strand)
      }
      let fatEnvelope = SCNNode(geometry: bodyEnvelope())
      fatEnvelope.simdScale = SIMD3(0.955, 0.99, 0.955)
      fatEnvelope.geometry?.materials = [material(gold, opacity: 0.014)]
      fatEnvelope.categoryBitMask = 2
      layerRoot(.fat).addChildNode(fatEnvelope)
    }

    private func tissueMaterial(_ label: TissueLabel) -> SCNMaterial {
      switch label {
      case .lungLeft, .lungRight:
        material(UIColor(red: 0.12, green: 0.59, blue: 0.88, alpha: 1), opacity: 0.62, glow: 0.12, metallic: 0.24)
      case .trachea:
        material(cyan, opacity: 0.65, glow: 0.1)
      case .boneCortical, .boneTrabecular:
        material(UIColor(red: 0.72, green: 0.87, blue: 0.94, alpha: 1), opacity: 0.40, glow: 0.04)
      case .heart, .aorta, .aneurysmLumen:
        material(coral, opacity: 0.96, glow: 0.08, metallic: 0.18)
      case .liver:
        material(UIColor(red: 0.82, green: 0.37, blue: 0.27, alpha: 1), opacity: 0.81, glow: 0.03)
      case .kidneyLeft, .kidneyRight:
        material(UIColor(red: 0.82, green: 0.40, blue: 0.57, alpha: 1), opacity: 0.92)
      case .spleen:
        material(UIColor(red: 0.61, green: 0.44, blue: 0.91, alpha: 1), opacity: 0.9)
      case .noduleLung, .cystLiver, .calculusKidney, .aneurysmThrombus:
        material(gold, opacity: 1, glow: 0.9)
      default:
        material(blue, opacity: 0.2)
      }
    }

    private func makeRibs(_ primitive: PhantomPrimitive, range: ClosedRange<Float>) {
      let material = tissueMaterial(.boneCortical)
      let step = primitive.zBand?.x ?? 24
      var z = range.lowerBound + 4
      while z <= range.upperBound {
        var points: [SIMD3<Float>] = []
        for index in 0...64 {
          let angle = Float(index) / 64 * .pi * 2
          points.append(SIMD3(
            primitive.halfAxes.x * cos(angle),
            z - 8 * (1 + sin(angle)),
            -primitive.halfAxes.y * sin(angle)
          ))
        }
        addTube(points, radius: 2.3, material: material, to: layerRoot(.bone))
        z += step
      }
    }

    private func makeSpine(_ primitive: PhantomPrimitive, range: ClosedRange<Float>) {
      for z in stride(from: range.lowerBound + 12, through: range.upperBound - 10, by: 25) {
        let vertebra = SCNNode(geometry: SCNBox(width: 29, height: 17, length: 31, chamferRadius: 6))
        vertebra.simdPosition = Self.scenePoint(SIMD3(primitive.center.x, primitive.center.y, z))
        vertebra.geometry?.materials = [tissueMaterial(.boneCortical)]
        layerRoot(.bone).addChildNode(vertebra)
      }
    }

    private func makeAirways() {
      let airwayMaterial = lineMaterial(UIColor(red: 0.49, green: 0.85, blue: 1, alpha: 1), opacity: 0.65)
      for side: Float in [-1, 1] {
        let central = SIMD3<Float>(0, 483, 10)
        let branch = SIMD3<Float>(side * 49, 437, -3)
        addTube([central, SIMD3(side * 22, 450, 4), branch], radius: 3.5, material: airwayMaterial, to: layerRoot(.lungs))
        for index in 0..<4 {
          let base = branch + SIMD3(side * Float(index) * 5, -Float(index) * 22, 0)
          let end = SIMD3<Float>(side * (85 + Float(index % 2) * 9), 455 - Float(index) * 36, -12 + Float(index % 2) * 32)
          addTube([base, (base + end) * 0.5 + SIMD3(0, 9, 0), end], radius: 1.6, material: airwayMaterial, to: layerRoot(.lungs))
          addTube([end, end + SIMD3(side * 7, 17, 7)], radius: 0.8, material: airwayMaterial, to: layerRoot(.lungs))
          addTube([end, end + SIMD3(side * 5, -17, -7)], radius: 0.8, material: airwayMaterial, to: layerRoot(.lungs))
        }
      }
    }

    private func bodyEnvelope() -> SCNGeometry {
      let profiles: [(Float, Float, Float)] = [
        (0, 104, 72), (35, 137, 93), (75, 154, 103), (145, 138, 100),
        (220, 137, 96), (300, 146, 99), (390, 161, 107), (465, 166, 108),
        (515, 148, 103), (551, 113, 87), (576, 76, 68)
      ]
      var points: [SCNVector3] = []
      var normals: [SCNVector3] = []
      var indices: [Int32] = []
      let count = 64
      for (z, xRadius, yRadius) in profiles {
        for index in 0...count {
          let angle = Float(index) / Float(count) * .pi * 2
          points.append(SCNVector3(xRadius * cos(angle), z, yRadius * sin(angle)))
          normals.append(SCNVector3(cos(angle), 0, sin(angle)))
        }
      }
      for row in 0..<(profiles.count - 1) {
        for column in 0..<count {
          let a = Int32(row * (count + 1) + column)
          let b = a + Int32(count + 1)
          indices += [a, b, a + 1, a + 1, b, b + 1]
        }
      }
      return SCNGeometry(sources: [SCNGeometrySource(vertices: points), SCNGeometrySource(normals: normals)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }

    private func makeSun() {
      let radii: [Float] = [165, 151, 135, 92, 42]
      let layers: [TissueLayer] = [.skin, .fat, .muscle, .bone, .blood]
      let colors: [UIColor] = [
        UIColor(red: 121 / 255, green: 68 / 255, blue: 184 / 255, alpha: 1),
        UIColor(red: 246 / 255, green: 57 / 255, blue: 83 / 255, alpha: 1),
        UIColor(red: 251 / 255, green: 113 / 255, blue: 45 / 255, alpha: 1),
        UIColor(red: 1, green: 205 / 255, blue: 78 / 255, alpha: 1),
        UIColor(red: 1, green: 251 / 255, blue: 203 / 255, alpha: 1)
      ]
      for index in radii.indices {
        let center = layerRoot(layers[index])
        center.position = SCNVector3(0, 288, 0)
        let shell = SCNNode(geometry: cutawaySphere(radius: radii[index]))
        shell.geometry?.materials = [material(colors[index], glow: index == 4 ? 1 : 0.35, metallic: 0)]
        center.addChildNode(shell)
        for angle: Float in [.pi / 2, .pi * 2] {
          let cap = SCNNode(geometry: shellFace(outer: radii[index], inner: index + 1 < radii.count ? radii[index + 1] : 0, angle: angle))
          cap.geometry?.materials = [material(colors[index], glow: 0.6, metallic: 0)]
          center.addChildNode(cap)
        }
      }
      for index in 0..<3 {
        let halo = SCNTorus(ringRadius: CGFloat(184 + index * 13), pipeRadius: index == 0 ? 0.8 : 0.4)
        let node = SCNNode(geometry: halo)
        node.geometry?.materials = [lineMaterial(gold, opacity: 0.28 - CGFloat(index) * 0.06)]
        node.eulerAngles = SCNVector3(0.3 + Float(index) * 0.4, 0.15, 0.1)
        node.position = SCNVector3(0, 288, 0)
        node.categoryBitMask = 2
        subjectRoot.addChildNode(node)
      }
    }

    private func cutawaySphere(radius: Float) -> SCNGeometry {
      var vertices: [SCNVector3] = []
      var normals: [SCNVector3] = []
      var indices: [Int32] = []
      let rows = 48, columns = 72
      for row in 0...rows {
        let latitude = Float(row) / Float(rows) * .pi
        for column in 0...columns {
          let longitude = .pi / 2 + Float(column) / Float(columns) * .pi * 1.5
          let p = SIMD3<Float>(sin(latitude) * cos(longitude), cos(latitude), sin(latitude) * sin(longitude))
          vertices.append(SCNVector3(p * radius))
          normals.append(SCNVector3(p))
        }
      }
      for row in 0..<rows {
        for column in 0..<columns {
          let a = Int32(row * (columns + 1) + column), b = a + Int32(columns + 1)
          indices += [a, a + 1, b, a + 1, b + 1, b]
        }
      }
      return SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }

    private func shellFace(outer: Float, inner: Float, angle: Float) -> SCNGeometry {
      var vertices: [SCNVector3] = []
      var indices: [Int32] = []
      for index in 0...64 {
        let latitude = Float(index) / 64 * .pi
        for radius in [outer, inner] {
          vertices.append(SCNVector3(radius * sin(latitude) * cos(angle), radius * cos(latitude), radius * sin(latitude) * sin(angle)))
        }
      }
      for index in 0..<64 {
        let a = Int32(index * 2)
        indices += [a, a + 1, a + 2, a + 1, a + 3, a + 2]
      }
      return SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }

    private func makeCircuit() {
      for level in 0..<4 {
        let height = Float(112 + level * 108)
        let board = SCNNode(geometry: SCNBox(width: 300, height: 9, length: 230, chamferRadius: 5))
        board.position = SCNVector3(0, height, 0)
        board.geometry?.materials = [material(UIColor(red: 0.025, green: 0.17 + CGFloat(level) * 0.015, blue: 0.19, alpha: 1), opacity: 0.94, metallic: 0.4)]
        layerRoot(.muscle).addChildNode(board)
        for column in 0..<5 {
          let x = Float(column * 49 - 98)
          let z = Float((column % 2 == 0 ? 1 : -1) * 63)
          let chip = SCNNode(geometry: SCNBox(width: 31, height: 13, length: 28, chamferRadius: 2))
          chip.position = SCNVector3(x, height + 11, z)
          chip.geometry?.materials = [material(UIColor(red: 0.05, green: 0.075, blue: 0.12, alpha: 1), metallic: 0.7)]
          layerRoot(.organs).addChildNode(chip)
          for side: Float in [-1, 1] {
            for pin in 0..<5 {
              let connector = SCNNode(geometry: SCNBox(width: 3, height: 2.5, length: 8, chamferRadius: 0.6))
              connector.position = SCNVector3(x - 12 + Float(pin * 6), height + 7, z + side * 17)
              connector.geometry?.materials = [material(gold, glow: 0.05, metallic: 0.85)]
              layerRoot(.bone).addChildNode(connector)
            }
          }
          let traceZ = Float(column * 12 - 24)
          addTube([SIMD3(x, height + 5, z), SIMD3(x, height + 5, traceZ), SIMD3(-x, height + 5, traceZ)], radius: 0.75, material: lineMaterial(cyan, opacity: 0.75), to: layerRoot(.blood))
        }
        let processor = SCNNode(geometry: SCNBox(width: 62, height: 12, length: 49, chamferRadius: 3))
        processor.position = SCNVector3(0, height + 11, 0)
        processor.geometry?.materials = [material(UIColor(red: 0.12, green: 0.20, blue: 0.30, alpha: 1), metallic: 0.8)]
        layerRoot(.organs).addChildNode(processor)
        let processorInset = SCNNode(geometry: SCNBox(width: 29, height: 1, length: 25, chamferRadius: 1))
        processorInset.position = SCNVector3(0, height + 17.5, 0)
        processorInset.geometry?.materials = [material(cyan, glow: 0.65, metallic: 0.7)]
        layerRoot(.organs).addChildNode(processorInset)
      }
      for x: Float in [-135, 135] {
        for z: Float in [-98, 98] {
          addTube([SIMD3(x, 96, z), SIMD3(x, 451, z)], radius: 3.5, material: material(gold, opacity: 0.7, metallic: 0.85), to: layerRoot(.bone))
        }
      }
    }

    private func makeReferenceRings() {
      let guide = SCNNode()
      scene.rootNode.addChildNode(guide)
      for radius: CGFloat in [180, 209] {
        let ring = SCNNode(geometry: SCNTorus(ringRadius: radius, pipeRadius: 0.5))
        ring.position = SCNVector3(0, -16, 0)
        ring.geometry?.materials = [lineMaterial(cyan, opacity: radius == 180 ? 0.24 : 0.10)]
        ring.categoryBitMask = 2
        guide.addChildNode(ring)
      }
      for index in 0..<48 {
        let angle = Float(index) / 48 * .pi * 2
        let major = index % 4 == 0
        let a = SIMD3<Float>(cos(angle) * 192, -16, sin(angle) * 192)
        let b = SIMD3<Float>(cos(angle) * (major ? 201 : 196), -16, sin(angle) * (major ? 201 : 196))
        addTube([a, b], radius: 0.5, material: lineMaterial(cyan, opacity: major ? 0.35 : 0.13), to: guide, category: 2)
      }
      for x: Float in [-212, 212] {
        addTube([SIMD3(x, 0, 0), SIMD3(x, 576, 0)], radius: 0.35, material: lineMaterial(cyan, opacity: 0.10), to: guide, category: 2)
        for height in stride(from: Float(0), through: 576, by: 48) {
          addTube([SIMD3(x - 3, height, 0), SIMD3(x + 3, height, 0)], radius: 0.4, material: lineMaterial(cyan, opacity: 0.25), to: guide, category: 2)
        }
      }
    }

    private func makeCutPlane() {
      let surface = SCNNode(geometry: SCNPlane(width: 400, height: 400))
      let fill = lineMaterial(cyan, opacity: 0.07)
      fill.readsFromDepthBuffer = false
      surface.geometry?.materials = [fill]
      surface.categoryBitMask = 2
      surface.renderingOrder = 20
      planeRoot.addChildNode(surface)
      let corners: [SIMD3<Float>] = [SIMD3(-200, -200, 0), SIMD3(200, -200, 0), SIMD3(200, 200, 0), SIMD3(-200, 200, 0), SIMD3(-200, -200, 0)]
      addTube(corners, radius: 0.75, material: lineMaterial(cyan, opacity: 0.7), to: planeRoot, category: 2)
      for x in stride(from: Float(-150), through: 150, by: 50) {
        addTube([SIMD3(x, -200, 0), SIMD3(x, 200, 0)], radius: 0.25, material: lineMaterial(cyan, opacity: 0.13), to: planeRoot, category: 2)
      }
      for y in stride(from: Float(-150), through: 150, by: 50) {
        addTube([SIMD3(-200, y, 0), SIMD3(200, y, 0)], radius: 0.25, material: lineMaterial(cyan, opacity: 0.13), to: planeRoot, category: 2)
      }
      for side: Float in [-1, 1] {
        addTube([SIMD3(side * 175, -200, 0), SIMD3(side * 200, -200, 0), SIMD3(side * 200, -175, 0)], radius: 1.7, material: lineMaterial(cyan), to: planeRoot, category: 2)
        addTube([SIMD3(side * 175, 200, 0), SIMD3(side * 200, 200, 0), SIMD3(side * 200, 175, 0)], radius: 1.7, material: lineMaterial(cyan), to: planeRoot, category: 2)
      }
      addTube([SIMD3(-200, 0, 0), SIMD3(200, 0, 0)], radius: 0.55, material: lineMaterial(cyan, opacity: 0.62), to: planeRoot, category: 2)
    }

    private func makeMarker() {
      let center = SCNNode(geometry: SCNSphere(radius: 4))
      center.geometry?.materials = [material(gold, glow: 1.2)]
      center.categoryBitMask = 2
      center.renderingOrder = 30
      markerRoot.addChildNode(center)
      for index in 0..<3 {
        let ring = SCNNode(geometry: SCNTorus(ringRadius: 10, pipeRadius: 0.55))
        ring.geometry?.materials = [lineMaterial(gold, opacity: 0.9)]
        ring.eulerAngles = index == 0 ? SCNVector3(0, 0, 0) : (index == 1 ? SCNVector3(Float.pi / 2, 0, 0) : SCNVector3(0, 0, Float.pi / 2))
        ring.categoryBitMask = 2
        ring.renderingOrder = 30
        markerRoot.addChildNode(ring)
      }
    }

    /// One triangle mesh per path keeps ribs, airways, and guides cheap to render.
    private func addTube(_ points: [SIMD3<Float>], radius: Float, material: SCNMaterial, to parent: SCNNode, category: Int = 1) {
      guard points.count >= 2 else { return }
      var vertices: [SCNVector3] = []
      var normals: [SCNVector3] = []
      var indices: [Int32] = []
      let sides = 8
      for index in points.indices {
        let prior = points[max(index - 1, 0)]
        let next = points[min(index + 1, points.count - 1)]
        let delta = next - prior
        let tangent = simd_length_squared(delta) > 0.0001 ? simd_normalize(delta) : SIMD3<Float>(0, 1, 0)
        let reference = abs(tangent.y) > 0.95 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
        let u = simd_normalize(simd_cross(tangent, reference))
        let v = simd_cross(tangent, u)
        for side in 0..<sides {
          let angle = Float(side) / Float(sides) * .pi * 2
          let normal = u * cos(angle) + v * sin(angle)
          vertices.append(SCNVector3(points[index] + normal * radius))
          normals.append(SCNVector3(normal))
        }
      }
      for index in 0..<(points.count - 1) {
        for side in 0..<sides {
          let a = Int32(index * sides + side)
          let b = Int32(index * sides + (side + 1) % sides)
          let c = a + Int32(sides), d = b + Int32(sides)
          indices += [a, c, b, b, c, d]
        }
      }
      let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
      geometry.materials = [material]
      let node = SCNNode(geometry: geometry)
      node.categoryBitMask = category
      parent.addChildNode(node)
    }
  }
}
