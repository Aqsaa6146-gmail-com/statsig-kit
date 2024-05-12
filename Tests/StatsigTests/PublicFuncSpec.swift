import Foundation

import XCTest
import Nimble
import OHHTTPStubs
import Quick
import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

final class PublicFuncSpec: BaseSpec {
    override func spec() {
        super.spec()

        describe("PublicFunc") {
            lazy var client: StatsigClient = {
                let handle = stub(condition: isHost("api.statsig.com")) { req in
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                var c: StatsigClient? = nil
                waitUntil { done in
                    c = StatsigClient(sdkKey: "client-key") { err in done() }
                }

                HTTPStubs.removeStub(handle)
                return c!
            }()


            it("has the same methods across client instances and the static interface") {
                let pairs = [
                    // Feature Gate
                    (t(Statsig.checkGate), t(client.checkGate)),
                    (t(Statsig.checkGateWithExposureLoggingDisabled), t(client.checkGateWithExposureLoggingDisabled)),
                    (t(Statsig.getFeatureGateWithExposureLoggingDisabled), t(client.getFeatureGateWithExposureLoggingDisabled)),
                    (t(Statsig.manuallyLogGateExposure), t(client.manuallyLogGateExposure)),
                    (t(Statsig.manuallyLogExposure as (FeatureGate) -> Void), t(client.manuallyLogExposure as (FeatureGate) -> Void)),

                    // Dynamic Configs
                    (t(Statsig.getConfig), t(client.getConfig)),
                    (t(Statsig.getConfigWithExposureLoggingDisabled), t(client.getConfigWithExposureLoggingDisabled)),
                    (t(Statsig.manuallyLogConfigExposure), t(client.manuallyLogConfigExposure)),
                    (t(Statsig.manuallyLogExposure as (DynamicConfig) -> Void), t(client.manuallyLogExposure as (DynamicConfig) -> Void)),
                    (t(Statsig.getConfig), t(client.getConfig)),

                    // Experiments
                    (t(Statsig.getExperiment), t(client.getExperiment)),
                    (t(Statsig.getExperimentWithExposureLoggingDisabled), t(client.getExperimentWithExposureLoggingDisabled)),
                    (t(Statsig.manuallyLogExperimentExposure), t(client.manuallyLogExperimentExposure)),

                    // Layers
                    (t(Statsig.getLayer), t(client.getLayer)),
                    (t(Statsig.getLayerWithExposureLoggingDisabled), t(client.getLayerWithExposureLoggingDisabled)),
                    (t(Statsig.manuallyLogLayerParameterExposure), t(client.manuallyLogLayerParameterExposure)),

                    // Local Overrides
                    (t(Statsig.overrideGate), t(client.overrideGate)),
                    (t(Statsig.overrideConfig), t(client.overrideConfig)),
                    (t(Statsig.overrideLayer), t(client.overrideLayer)),
                    (t(Statsig.removeOverride), t(client.removeOverride)),
                    (t(Statsig.removeAllOverrides), t(client.removeAllOverrides)),
                    
                    // Manually Refresh Cache
                    (t(Statsig.refreshCache()), t(client.refreshCache())),

                    // Log Event
                    (t(Statsig.logEvent as (String, [String: String]) -> Void), t(client.logEvent as (String, [String: String]) -> Void)),
                    (t(Statsig.logEvent as (String, String, [String: String]) -> Void), t(client.logEvent as (String, String, [String: String]) -> Void)),
                    (t(Statsig.logEvent as (String, Double, [String: String]) -> Void), t(client.logEvent as (String, Double, [String: String]) -> Void)),

                    // Misc
                    (t(Statsig.shutdown), t(client.shutdown)),
                    (t(Statsig.flush), t(client.flush)),
                    (t(Statsig.getInitializeResponseJson), t(client.getInitializeResponseJson)),
                    (t(Statsig.updateUser), t(client.updateUser)),
                    (t(Statsig.getStableID), t(client.getStableID)),
                    (t(Statsig.isInitialized), t(client.isInitialized)),
                    (t(Statsig.addListener), t(client.addListener)),
                    (t(Statsig.openDebugView), t(client.openDebugView)),
                ]

                for (instance, interface) in pairs {
                    expect(instance).to(equal(interface))
                }
            }
        }
    }
}

fileprivate func t<T>(_ input: T?) -> String {
    return "\(type(of: input))"
}
