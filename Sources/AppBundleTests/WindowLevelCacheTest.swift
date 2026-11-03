@testable import AppBundle
import XCTest

final class WindowLevelCacheTest: XCTestCase {
    @MainActor func testOverlappingCacheMissesBothComplete() async {
        let loading = expectation(description: "cache load started")
        let finished = expectation(description: "both lookups completed")
        finished.expectedFulfillmentCount = 2
        let gate = AwaitableOneTimeBroadcastLatch()
        let first = Task { @MainActor in
            _ = try? await getWindowLevel(forNativeId: UInt32.max, .cancellable, load: {
                loading.fulfill()
                try? await gate.await(.nonCancellable)
                return [:]
            })
            finished.fulfill()
        }
        await fulfillment(of: [loading], timeout: 2)
        let second = Task { @MainActor in
            _ = try? await getWindowLevel(forNativeId: UInt32.max - 1, .cancellable)
            finished.fulfill()
        }
        try? await Task.sleep(for: .milliseconds(50))
        await gate.signalToAll()
        await fulfillment(of: [finished], timeout: 2)
        first.cancel()
        second.cancel()
    }
}
