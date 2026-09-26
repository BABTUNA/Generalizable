import Foundation
import simd

/// One point of interest, either authored for the sample case or pulled out of an imported report.
struct Finding: Identifiable, Codable, Equatable, Hashable {
  enum Tone: String, Codable {
    /// Usually harmless.
    case reassuring
    /// Worth keeping an eye on.
    case routine
    /// Worth a prompt conversation with your doctor.
    case attention

    var displayName: String {
      switch self {
      case .reassuring: "Usually harmless"
      case .routine: "Worth watching"
      case .attention: "Ask your doctor soon"
      }
    }

    var symbolName: String {
      switch self {
      case .reassuring: "checkmark.circle"
      case .routine: "eye"
      case .attention: "exclamationmark.circle"
      }
    }
  }

  var id: UUID = UUID()
  var title: String
  var clinicalPhrase: String
  var region: BodyRegion
  var anchor: [Float]
  var sizeMM: Float?
  var plainSummary: String
  var whatItMeans: String
  var questionsForDoctor: [String]
  var tone: Tone
  var labelRaw: UInt8?

  var anchorMM: SIMD3<Float> {
    get { anchor.count == 3 ? SIMD3(anchor[0], anchor[1], anchor[2]) : region.anchorMM }
    set { anchor = [newValue.x, newValue.y, newValue.z] }
  }

  var label: TissueLabel? { labelRaw.flatMap(TissueLabel.init(rawValue:)) }

  init(title: String, clinicalPhrase: String, region: BodyRegion, anchorMM: SIMD3<Float>? = nil, sizeMM: Float?, plainSummary: String, whatItMeans: String, questionsForDoctor: [String], tone: Tone, label: TissueLabel? = nil) {
    self.title = title
    self.clinicalPhrase = clinicalPhrase
    self.region = region
    let a = anchorMM ?? region.anchorMM
    self.anchor = [a.x, a.y, a.z]
    self.sizeMM = sizeMM
    self.plainSummary = plainSummary
    self.whatItMeans = whatItMeans
    self.questionsForDoctor = questionsForDoctor
    self.tone = tone
    self.labelRaw = label?.rawValue
  }
}
