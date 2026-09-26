# Generalizable — Engineering contract (engine layer)

This file is the source of truth for types shared between files written by different people.
Match names and signatures exactly. Everything here is plain Swift + SwiftUI/CoreGraphics/simd/
FoundationModels available in the iOS 26.5 SDK, so it compiles for a deployment target of iOS 26.0.
Duo-only APIs (iOS 27.1) live only in the UI layer behind `if #available(iOS 27.1, *)`.

Precedent rule (project standing instruction): every non-trivial algorithm follows a named open-source
project and cites its file. The research notes with verified permalinks are in
`docs/research-slicing.md`, `docs/research-phantom.md`, `docs/research-claude-api.md`.
Put the citation in a comment at the top of the function or type that copies it.

Code style: 2-space indentation, one primary type per file, `var` for struct stored properties,
strong enums for fixed sets, no `#Preview`, no PreviewProvider.

Type-check command (run from the project root; must pass with zero errors before you finish):

    SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
    xcrun swiftc -typecheck -sdk "$SDK" -target arm64-apple-ios26.0-simulator -swift-version 5 $(find App -name '*.swift')

Numeric verification: write throwaway scripts under /tmp (never in App/) and run them with
`xcrun swiftc -O -sdk "$SDK" -target arm64-apple-ios26.0-simulator ...` is NOT runnable on macOS;
instead compile verification programs for macOS with `swiftc -O -o /tmp/verify /tmp/verify.swift <engine files>`
(the engine files must not import UIKit; `import CoreGraphics`, `simd`, `Foundation` are fine on macOS).

## 1. Coordinate convention — `App/Engine/Geometry/PatientSpace.swift`

DICOM/ITK **LPS** voxel order (3D Slicer coordinate_systems doc; see research-phantom §1).

| axis | + direction | index 0 at |
|---|---|---|
| x (i) | patient **L**eft | patient right |
| y (j) | **P**osterior | anterior (front) |
| z (k) | **S**uperior | inferior (feet) |

```swift
import simd

/// World (mm) ↔ voxel conventions for every scan in the app. LPS like DICOM/ITK.
enum PatientSpace {
  static let dims = SIMD3<Int>(128, 128, 192)
  static let spacingMM: Float = 3
  /// mm position of the centre of voxel (0,0,0). Torso centre is (0,0); z=0 is the inferior edge.
  static let originMM = SIMD3<Float>(-64 * 3, -64 * 3, 0)
  static let extentMM = SIMD3<Float>(384, 384, 576)
  static let left = SIMD3<Float>(1, 0, 0)
  static let posterior = SIMD3<Float>(0, 1, 0)
  static let superior = SIMD3<Float>(0, 0, 1)
  static var anterior: SIMD3<Float> { -posterior }
  static var right: SIMD3<Float> { -left }
  static func mm(fromVoxel v: SIMD3<Float>) -> SIMD3<Float>     // originMM + v * spacingMM
  static func voxel(fromMM p: SIMD3<Float>) -> SIMD3<Float>     // (p - originMM) / spacingMM, continuous
  static var centerMM: SIMD3<Float> { SIMD3(0, 0, extentMM.z / 2) }
}
```

Radiological display rules (no flips needed): axial image column = i (screen-left = patient right),
row = j (top = anterior). Coronal: column = i, row top = superior. Sagittal: column = j (screen-left = anterior), row top = superior.

## 2. Cut plane — `App/Engine/Geometry/CutPlane.swift`

Copy of 3D Slicer `vtkMRMLSliceNode` SliceToRAS / VTK `vtkImageReslice::ResliceAxes` columns `[u, v, n, origin]`
(research-slicing §1). All vectors in mm world space.

```swift
import simd
import CoreGraphics

struct CutPlane: Equatable {
  var center: SIMD3<Float>          // mm, centre of the field of view
  var u: SIMD3<Float>               // unit, screen right
  var v: SIMD3<Float>               // unit, screen up
  var n: SIMD3<Float>               // unit, == simd_cross(u, v)  (right-handed; Slicer sign(det) rule)
  var fovMM: SIMD2<Float>           // field of view (width, height) in mm

  init(center: SIMD3<Float>, u: SIMD3<Float>, v: SIMD3<Float>, fovMM: SIMD2<Float>)   // normalizes, sets n = cross(u,v)

  /// Slicer SetSliceToRASByNTP: build (u,v) from a normal and an up hint.
  static func from(normal: SIMD3<Float>, upHint: SIMD3<Float>, center: SIMD3<Float>, fovMM: SIMD2<Float>) -> CutPlane

  // Presets (research-slicing §1 table, LPS-adapted; see verification values below)
  static func axial(levelZ: Float, fovMM: SIMD2<Float>) -> CutPlane      // u=(1,0,0) v=(0,-1,0) n=(0,0,-1) center=(0,0,levelZ)
  static func coronal(y: Float, fovMM: SIMD2<Float>) -> CutPlane         // u=(1,0,0) v=(0,0,1)  n=(0,-1,0) center=(0,y,extent.z/2)
  static func sagittal(x: Float, fovMM: SIMD2<Float>) -> CutPlane        // u=(0,1,0) v=(0,0,1)  n=(1,0,0)  center=(x,0,extent.z/2)

  /// The hinge cut. Contains the patient left–right line through `pivot`, tilted `tiltDegrees`
  /// away from the axial plane toward the coronal plane (0 = axial, 90 = coronal). Rotation is
  /// T(pivot)·R(x̂, −tilt)·T(−pivot) applied to the axial basis (Slicer vtkMRMLSliceIntersectionWidget::Rotate,
  /// Cornerstone CrosshairsTool). MUST satisfy: tilt 0 == axial(levelZ: pivot.z); tilt 90 → v ≈ (0,0,1), n ≈ (0,−1,0).
  static func hinged(pivot: SIMD3<Float>, tiltDegrees: Float, fovMM: SIMD2<Float>) -> CutPlane

  /// Pixel-centre mapping (Cornerstone PlanarCPUVolumeSampler: xStart = -w/2 + step/2; rows go down = −v).
  func topLeftMM(width: Int, height: Int) -> SIMD3<Float>
  func columnStepMM(width: Int) -> SIMD3<Float>      // u * fov.x / width
  func rowStepMM(height: Int) -> SIMD3<Float>        // -v * fov.y / height
  func worldPoint(column: Int, row: Int, width: Int, height: Int) -> SIMD3<Float>

  /// Project a world point onto this plane's image (drops the normal component). Slicer rasToXY.
  func imagePoint(of world: SIMD3<Float>, imageSize: CGSize) -> CGPoint
  /// Signed distance of a world point from the plane along n (for "is the finding on this slice" and marker fading).
  func distance(to world: SIMD3<Float>) -> Float
  /// Where `other` cuts through this plane's image: Slicer IntersectWithFinitePlane + Cornerstone ReferenceLinesTool.
  /// nil when parallel (|dot(n, other.n)| > 1 - 1e-5) or when fewer than two edge hits.
  func intersectionSegment(with other: CutPlane, imageSize: CGSize) -> (CGPoint, CGPoint)?
  /// Translate along the normal (Slicer SetSliceOffset).
  func offset(by mm: Float) -> CutPlane
}
```

## 3. Tissue labels, layers, HU, colours — `App/Engine/Phantom/TissueLabel.swift`, `TissueLayer.swift`

Colours are verbatim 3D Slicer `GenericAnatomyColors.txt`; HU means/σ from Radiopaedia/Wikipedia; both tabulated in
research-phantom §2–§3. One sanctioned deviation: the Lungs layer colour uses Slicer's `trachea` blue
(182,228,255) instead of Slicer's tan lung colour, because tan is unreadable next to skin; say so in a comment.

```swift
enum TissueLabel: UInt8, CaseIterable, Codable {
  case air = 0, skin = 1, fat = 2, muscle = 3, boneCortical = 4, boneTrabecular = 5
  case lungRight = 6, lungLeft = 7, heart = 8, liver = 9, spleen = 10, kidneyRight = 11, kidneyLeft = 12
  case aorta = 13, trachea = 14, spinalCanal = 15
  case noduleLung = 20, aneurysmLumen = 21, aneurysmThrombus = 22, cystLiver = 23, calculusKidney = 24

  var displayName: String
  var huMean: Float            // research-phantom §3 "Demo mean HU"
  var huSigma: Float           // research-phantom §3 "Demo σ HU"
  var color: SIMD4<UInt8>      // RGBA, Slicer GenericAnatomyColors (findings: cyst 205,205,100; nodule 'mass' 144,238,144; stone: bone colour; aneurysm: aorta colour)
  var layer: TissueLayer?      // nil for air; findings map to the layer of their host organ (nodule→lungs, aneurysm→blood, cyst→organs, stone→organs)
  var isFinding: Bool          // rawValue >= 20
}

/// The seven peelable layers, ordered outside → inside. Visibility is a UI overlay concept, not anatomy.
enum TissueLayer: String, CaseIterable, Codable, Identifiable {
  case skin, fat, muscle, bone, lungs, organs, blood
  var id: String { rawValue }
  var displayName: String       // "Skin", "Fat", "Muscle", "Bone", "Lungs", "Organs", "Blood"
  var patientDescription: String  // one plain sentence, e.g. "The outer covering of your body."
  var color: Color (SwiftUI)     // representative colour for chips/legend — put this in an extension in the UI layer, NOT here; here expose `rgba: SIMD4<UInt8>`
  var rgba: SIMD4<UInt8>
  var labels: [TissueLabel]      // Skin{skin} Fat{fat} Muscle{muscle} Bone{boneCortical,boneTrabecular} Lungs{lungRight,lungLeft,trachea,noduleLung} Organs{liver,spleen,kidneyRight,kidneyLeft,cystLiver,calculusKidney} Blood{heart,aorta,aneurysmLumen,aneurysmThrombus}
  var symbolName: String         // SF Symbol verified to exist on iOS 26 (use the sf-symbols-catalog skill)
}
```

## 4. Phantom primitives and the volume source — `App/Engine/Phantom/`

Files: `PhantomPrimitive.swift`, `PatientPhantom.swift`, `VolumeSource.swift`, `AnalyticPhantomSource.swift`,
`VoxelVolume.swift`, `NoiseHash.swift`.

```swift
/// ODL `_ellipsoid_phantom_3d` / TomoPhantom `Object : ellipsoid` row, in mm with a label (XCIST .ppm style).
struct PhantomPrimitive: Codable, Equatable {
  enum Kind: String, Codable { case ellipsoid, ellipticCylinder }
  var kind: Kind
  var label: TissueLabel
  var center: SIMD3<Float>            // mm, LPS
  var halfAxes: SIMD3<Float>          // mm (a, b, c); for ellipticCylinder c is ignored
  var eulerDeg: SIMD3<Float> = .zero  // ODL ZXZ (phi, theta, psi)
  var zRange: ClosedRange<Float>? = nil   // ellipticCylinder only
  var zBandPeriod: Float? = nil       // optional periodic mask (ribs, discs): inside iff ((z - zRange.lowerBound) mod period) < zBandWidth
  var zBandWidth: Float? = nil
  func contains(_ p: SIMD3<Float>) -> Bool   // analytic test (ODL: rotate (p−c), sum of (d/a)^2 ≤ 1)
  var boundingBoxMM: (min: SIMD3<Float>, max: SIMD3<Float>)
}

/// The synthetic patient: exactly the table in research-phantom §7, in paint order (soft shells → lungs/trachea →
/// heart → liver/spleen/kidneys → aorta → bone → findings). Findings are the last four entries.
enum PatientPhantom {
  static let primitives: [PhantomPrimitive]
  /// Last-painted primitive containing p wins (painter's algorithm ⇒ iterate reversed). .air if none.
  static func label(atMM p: SIMD3<Float>) -> TissueLabel
  static let findingAnchorsMM: [TissueLabel: SIMD3<Float>]   // nodule (−75,−15,500), aneurysm (12,20,175), cyst (−80,−10,280), stone (46,50,205)
}

/// Anything the cross-section sampler can cut. Thread-safe, pure functions.
protocol VolumeSource: Sendable {
  var extentMM: SIMD3<Float> { get }
  var originMM: SIMD3<Float> { get }
  /// nearest label at a world point; .air outside the volume
  func label(atMM p: SIMD3<Float>) -> TissueLabel
  /// Hounsfield value at a world point; −1000 outside
  func hu(atMM p: SIMD3<Float>) -> Float
}

/// Crisp analytic evaluation (ODL docstring: a 3D phantom can be evaluated as a slice). HU follows SynthSeg
/// SampleConditionalGMM: mean[label] + σ[label]·N(0,1), with N(0,1) from a deterministic integer hash of the
/// position quantized to 1 mm (Box–Muller over two 32-bit hashes) so the grain is fixed in 3D as the plane tilts.
struct AnalyticPhantomSource: VolumeSource { init() }

/// ODL-style rasterization of the primitive list into label + HU voxel arrays (VTK/open-dicom-viewer index order
/// x + nx*(y + ny*z)). Used for the silhouette mini-map and as the general path for real volumes later.
final class VoxelVolume: VolumeSource, @unchecked Sendable {
  let dims: SIMD3<Int>; let spacingMM: Float; let originMM: SIMD3<Float>
  let labels: [UInt8]; let hu: [Int16]
  init(dims: SIMD3<Int>, spacingMM: Float, originMM: SIMD3<Float>, labels: [UInt8], hu: [Int16])
  /// Rasterize with an integer bounding box per primitive (ODL _getshapes_3d) using DispatchQueue.concurrentPerform over z.
  static func rasterize(_ primitives: [PhantomPrimitive], dims: SIMD3<Int>, spacingMM: Float, originMM: SIMD3<Float>) -> VoxelVolume
  func label(atMM:) / hu(atMM:)   // nearest (VTK Nearest: floor(i + 0.5 − 1e-6), clamp) for labels; trilinear for HU (VTK vtkImageNLCInterpolate::Trilinear)
}

enum NoiseHash {
  static func gaussian(_ p: SIMD3<Int32>, seed: UInt32) -> Float   // deterministic N(0,1)
}
```

## 5. Rendering — `App/Engine/Rendering/`

Files: `WindowPreset.swift`, `CrossSectionSampler.swift`, `SilhouetteRenderer.swift`, `RenderOptions.swift`.

```swift
/// 3D Slicer VolumeDisplayPresets.json values; gray mapping = cornerstone3D toLowHighRange LINEAR.
enum WindowPreset: String, CaseIterable, Codable {
  case lung, abdomen, bone, softTissue
  var window: Float   // lung 1400, abdomen 350, bone 1000, softTissue 400
  var level: Float    // lung −500, abdomen 40, bone 400, softTissue 50
  var displayName: String
  func gray(_ hu: Float) -> UInt8   // lower = L − 0.5 − (W−1)/2, upper = L − 0.5 + (W−1)/2, clamp
}

struct RenderOptions: Equatable {
  enum Mode: Equatable { case layers, ct }
  var mode: Mode = .layers
  var visibleLayers: Set<TissueLayer> = Set(TissueLayer.allCases)
  var windowPreset: WindowPreset = .abdomen
  var highlightFindings: Bool = true       // findings drawn even if their layer is hidden, in their label colour
  var outsideColor: SIMD4<UInt8> = SIMD4(0, 0, 0, 0)   // Slicer background (0,0,0,0)
}

/// CPU oblique reslice into an RGBA8 CGImage. Copies VTK vtkImageResliceExecute's per-row/per-column incremental
/// stepping and open-dicom-viewer MPREngine.obliqueSlice → CGContext. Double-buffered; safe to call from a
/// background task; never call concurrently on the same instance.
final class CrossSectionSampler<S: VolumeSource> {
  let source: S
  let width: Int, height: Int
  init(source: S, width: Int = 256, height: Int = 256)
  /// Fills the back buffer using DispatchQueue.concurrentPerform over rows, then returns a CGImage that owns a copy.
  func render(plane: CutPlane, options: RenderOptions) -> CGImage
}

/// Coronal (front) and sagittal (side) silhouettes of a VoxelVolume for the body mini-map: for each column, the
/// outermost non-air label along the projection axis wins (a "first-hit" projection; MIP in Cornerstone terms),
/// coloured with TissueLabel.color. Cached after first render.
final class SilhouetteRenderer {
  init(volume: VoxelVolume)
  func coronal(width: Int, height: Int) -> CGImage      // column = i, row top = superior
  func sagittal(width: Int, height: Int) -> CGImage     // column = j, row top = superior
}
```

## 6. Cases and findings — `App/Engine/Cases/`

Files: `BodyRegion.swift`, `Finding.swift`, `ScanCase.swift`, `SampleCases.swift`.

```swift
/// Where a report sentence points in the body. Anchors are in PatientPhantom mm space (research-phantom §7).
enum BodyRegion: String, CaseIterable, Codable {
  case rightLungUpperLobe, rightLungMiddleLobe, rightLungLowerLobe, leftLungUpperLobe, leftLungLowerLobe, trachea
  case heart, thoracicAorta, abdominalAorta, iliacArteries
  case liverRightLobe, liverLeftLobe, gallbladder, spleen, pancreas, stomach
  case rightKidney, leftKidney, rightAdrenal, leftAdrenal, bladder, pelvis
  case thoracicSpine, lumbarSpine, ribs, sternum, pelvicBones
  case skin, subcutaneousFat, abdominalWall, unknown
  var displayName: String
  var anchorMM: SIMD3<Float>          // inside the matching phantom organ; unknown → PatientSpace.centerMM
  var layer: TissueLayer              // layer to reveal when selected
  var windowPreset: WindowPreset      // lungs → .lung, bones → .bone, else .abdomen
}

/// One authored or imported point of interest.
struct Finding: Identifiable, Codable, Equatable {
  var id: UUID
  var title: String                  // "Lung nodule"
  var clinicalPhrase: String         // "Pulmonary nodule, 14 mm, right upper lobe"
  var region: BodyRegion
  var anchorMM: SIMD3<Float>         // defaults to region.anchorMM; authored findings use PatientPhantom.findingAnchorsMM
  var sizeMM: Float?                 // 14
  var plainSummary: String           // 1–2 sentences, 8th-grade reading level
  var whatItMeans: String            // a short paragraph, non-diagnostic
  var questionsForDoctor: [String]
  var tone: Tone                     // .reassuring / .routine / .attention  (never "urgent" language in demo copy)
  enum Tone: String, Codable { case reassuring, routine, attention }
  var label: TissueLabel?            // for authored findings, the phantom label to highlight
}

struct ScanCase: Identifiable, Codable, Equatable {
  var id: UUID
  var title: String                  // "Sample chest & abdomen CT"
  var subtitle: String               // "Synthetic demo — not a diagnosis"
  var kind: Kind
  enum Kind: String, Codable { case sample, imported }
  var findings: [Finding]
  var createdAt: Date
  var sourceFileName: String?
}

enum SampleCases {
  /// The bundled patient case with the four authored findings (copy from the PRD + research-phantom §9 clinical numbers).
  static let patientCT: ScanCase
}
```

Authored copy tone: plain words, no jargon without an inline gloss, never diagnose, always end with what to ask.
Each finding's `whatItMeans` must cite the size thresholds from research-phantom §9 in plain language
(e.g. "Nodules between 6 and 30 mm are usually watched with a follow-up scan; the size and shape decide how soon").

## 7. AI client — `App/AI/`

Files: `AnthropicClient.swift`, `StreamEvent.swift`, `APIError.swift`, `APIKeyStore.swift`, `RetryPolicy.swift`,
`ExplanationProvider.swift`, `OnDeviceProvider.swift`, `BundledProvider.swift`, `FallbackExplanationProvider.swift`,
`ClaudeModel.swift`. Follow research-claude-api §1–§6 exactly (Anthropic's own `ClaudeForFoundationModels` client is
the precedent for the client, SSE handling, errors and Keychain; the official Python SDK for retry constants).

```swift
enum ClaudeModel: String, CaseIterable, Codable {
  case opus5 = "claude-opus-5"          // default
  case sonnet5 = "claude-sonnet-5"      // "Fast"
  case fable51 = "claude-fable-5-1"     // "Most capable" (opt-in; structured output via output_config.format only)
  var displayName: String
}

protocol ExplanationProvider: Sendable {
  var sourceName: String { get }        // "Claude", "On-device", "Offline copy" — shown as a caption
  /// Cumulative text snapshots (ClaudeClient.streamText semantics).
  func streamText(system: String, user: String) -> AsyncThrowingStream<String, Error>
  /// Schema-guaranteed JSON (output_config.format json_schema). `attachments` are PDF bytes sent as document blocks.
  func structured(system: String, user: String, schema: [String: Any], attachments: [Data]) async throws -> Data
}

struct AnthropicClient: ExplanationProvider {
  struct Configuration: Equatable {
    var apiKey: String
    var model: ClaudeModel = .opus5
    var baseURL: URL = URL(string: "https://api.anthropic.com")!
    var version: String = "2023-06-01"
    var useServerFallbacks: Bool = false   // beta header can 400 for orgs not enrolled; keep off by default
  }
  init(configuration: Configuration, session: URLSession = .shared)
}

struct APIKeyStore {                       // Keychain, research-claude-api §4
  static let shared = APIKeyStore()
  func read() throws -> String?
  func write(_ key: String) throws         // trims; empty → delete
  func delete() throws
}

/// Apple FoundationModels tier (iOS 26): SystemLanguageModel.default.availability == .available.
struct OnDeviceProvider: ExplanationProvider { static var isAvailable: Bool }
/// Streams authored copy in ~40-char chunks with a 30 ms sleep so the UI path is identical offline.
struct BundledProvider: ExplanationProvider { init(text: String) }
/// Tries Anthropic (if a key exists) → on-device → bundled. `structured` only works on Anthropic; else throws .unavailable.
struct FallbackExplanationProvider: ExplanationProvider {
  init(anthropic: AnthropicClient?, onDevice: OnDeviceProvider?, bundledText: String)
}

enum AnthropicError: Error, LocalizedError {
  case api(APIError), transport(URLError), decoding(Error), refused(category: String?), truncated(partial: String)
  case missingCredential, unavailable, cancelled
}
```

Prompts live in `App/AI/Prompts.swift`:
- `Prompts.patientSystem` — explains scan findings to a patient at an 8th-grade level; never diagnoses; says what the report says, what it usually means, and what to ask; names the seven layers; refuses to give treatment advice.
- `Prompts.reportSystem` — same voice, for turning a report into the structured schema.
- `Prompts.explain(finding:)`, `Prompts.ask(question:context:)`.

Never send temperature/top_p/top_k. Set `output_config.effort` = "low" for streamed explanations and "medium"
for structured extraction. `max_tokens` 8192 (stream) / 16000 (structured). Branch on `stop_reason` before parsing.

## 8. Not in the engine layer

UI (views, view models, hinge input, ArrangementView, file import, report interpretation) is specified separately in
`docs/UISpec.md` once the design is final. Engine files must not import UIKit or SwiftUI, except `Color` helpers that
belong in the UI layer anyway.
