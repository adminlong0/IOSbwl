import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct NLBUSActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var destination: String
    var nextStation: String
    var remainingStops: Int
    var distanceText: String
    var vehicleNumber: String
    var updatedAt: Date
  }

  var lineName: String
  var direction: String
  var targetStation: String
  var accentHex: String
}
