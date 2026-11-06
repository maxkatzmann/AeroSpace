import Foundation

extension TimeInterval {
    static func withTimestamp(_ timeStamp: String) -> TimeInterval? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSSS"

        // Create a reference date for today with time set to the parsed time
        guard let date = formatter.date(from: timeStamp) else {
            return nil
        }

        // Return seconds since reference (midnight)
        return date.timeIntervalSince(Calendar.current.startOfDay(for: date))
    }
}
