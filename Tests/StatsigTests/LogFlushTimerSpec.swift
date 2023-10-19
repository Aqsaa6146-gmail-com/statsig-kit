import Nimble
import OHHTTPStubs
import Quick

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

@testable import Statsig

class LogFlushTimerSpec: BaseSpec {
    override func spec() {
        super.spec()

        let user = StatsigUser(userID: "jkw")

        var logger: SpiedEventLogger!

        describe("LogFlushTimer") {
            beforeEach {
                   let key = "client-key"
                let opts = StatsigOptions()
                let store = InternalStore(key, user, options: opts)
                let network = NetworkService(sdkKey: key, options: opts, store: store)
                logger = SpiedEventLogger(user: user, networkService: network, userDefaults: MockDefaults())
            }

            it("invalidates previous timers") {
                logger.start()
                logger.start()

                expect(logger.timerInstances.count).toEventually(equal(2))
                expect(logger.timerInstances[0].isValid).to(beFalse())
            }

            it("fires timers regardless of starting thread") {
                DispatchQueue.global(qos: .background).async {
                    logger.start(flushInterval: 0.001)
                }

                expect(logger.timesFlushCalled).toEventually(beGreaterThanOrEqualTo(1))
            }
        }
    }
}
