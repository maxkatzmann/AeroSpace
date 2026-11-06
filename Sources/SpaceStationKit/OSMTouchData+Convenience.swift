import Foundation
import OpenMultitouchSupport

extension OMSTouchData {

    var time: TimeInterval? {
        return TimeInterval.withTimestamp(self.timestamp)
    }

    var point: CGPoint {
        return CGPoint(x: Double(self.position.x), y: Double(self.position.y))
    }
}
