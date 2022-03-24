import Foundation

import Nimble
import Quick
@testable import Statsig

class InternalStoreSpec: QuickSpec {
    private func cacheIsEmpty(_ cache: [String: Any]) -> Bool {
        return
            (cache[InternalStore.gatesKey] as! [String: Any]).count == 0
                && (cache[InternalStore.configsKey] as! [String: Any]).count == 0
                && (cache[InternalStore.stickyExpKey] as! [String: Any]).count == 0
                && (cache["time"] as? Int) == 0
    }

    override func spec() {
        describe("using internal store to save and retrieve values") {
            beforeEach {
                InternalStore.deleteAllLocalStorage()
            }

            it("is empty initially") {
                let store = InternalStore(StatsigUser())
                expect(self.cacheIsEmpty(store.cache.userCache)).to(beTrue())
            }

            it("sets value in UserDefaults correctly and persists between initialization") {
                let store = InternalStore(StatsigUser())
                waitUntil(timeout: .seconds(1)) { done in
                    store.set(values: StatsigSpec.mockUserValues) {
                        done()
                    }
                }

                let store2 = InternalStore(StatsigUser())
                let cache = store2.cache.userCache
                expect(cache).toNot(beNil())
                expect((cache["feature_gates"] as! [String: [String: Any]]).count).to(equal(2))
                expect((cache["dynamic_configs"] as! [String: [String: Any]]).count).to(equal(1))

                let gate1 = store.checkGate(forName: "gate_name_1")
                expect(gate1?.value).to(beFalse())
                expect(gate1?.secondaryExposures[0]).to(equal(["gate": "employee", "gateValue": "true", "ruleID": "rule_id_employee"]))
                expect(store.checkGate(forName: "gate_name_2")?.value).to(beTrue())
                expect(store.getConfig(forName: "config")?.getValue(forKey: "str", defaultValue: "wrong")).to(equal("string"))

                InternalStore.deleteAllLocalStorage()
                expect(self.cacheIsEmpty(InternalStore(StatsigUser()).cache.userCache)).to(beTrue())
            }

            it("migrates old values to new cache") {
                // set up deprecated cache
                let configKey = "config"
                let gateKey = "gate"
                let hashConfigKey = configKey.sha256()
                let hashGateKey = gateKey.sha256()
                let values: [String: [String: Any]] = [
                    "dynamic_configs": [
                        hashConfigKey: [
                            "rule_id": "default",
                            "value": ["key": "value"],
                            "is_user_in_experiment": true,
                            "is_experiment_active": true,
                        ],
                    ],
                    "feature_gates": [
                        hashGateKey: ["value": true, "rule_id": "rule_id_2"]
                    ]
                ]
                let stickyValues = [
                    hashConfigKey: [
                        "rule_id": "sticky",
                        "value": ["key": "value_sticky"],
                    ],
                ]
                UserDefaults.standard.setValue(values, forKey: InternalStore.DEPRECATED_localStorageKey)
                UserDefaults.standard.setValue("jkw", forKey: InternalStore.DEPRECATED_stickyUserIDKey)
                UserDefaults.standard.setValue(stickyValues, forKey: InternalStore.DEPRECATED_stickyUserExperimentsKey)

                let store = InternalStore(StatsigUser(userID: "jkw"))
                var gate = store.checkGate(forName: gateKey)
                expect(gate!.value).to(beTrue())

                var config = store.getConfig(forName: configKey)
                expect(config!.getValue(forKey: "key", defaultValue: "")).to(equal("value"))

                var exp = store.getExperiment(forName: configKey, keepDeviceValue: true)
                expect(exp!.getValue(forKey: "key", defaultValue: "")).to(equal("value_sticky"))

                // old values should be deleted
                expect(UserDefaults.standard.dictionary(forKey: InternalStore.DEPRECATED_localStorageKey)).to(beNil())
                expect(UserDefaults.standard.string(forKey: InternalStore.DEPRECATED_stickyUserIDKey)).to(beNil())
                expect(UserDefaults.standard.dictionary(forKey: InternalStore.DEPRECATED_stickyUserExperimentsKey)).to(beNil())

                // Update to new values; sticky should still be sticky
                let newValues: [String: Any] = [
                    "dynamic_configs": [
                        hashConfigKey: [
                            "rule_id": "default",
                            "value": ["key": "value_new"],
                            "is_user_in_experiment": true,
                            "is_experiment_active": true,
                        ],
                    ],
                    "feature_gates": [
                        hashGateKey: ["value": false, "rule_id": "rule_id_2"]
                    ],
                    "time": 12345
                ]
                store.set(values: newValues)
                gate = store.checkGate(forName: gateKey)
                expect(gate!.value).to(beFalse())

                config = store.getConfig(forName: configKey)
                expect(config!.getValue(forKey: "key", defaultValue: "")).to(equal("value_new"))

                exp = store.getExperiment(forName: configKey, keepDeviceValue: true)
                expect(exp!.getValue(forKey: "key", defaultValue: "")).to(equal("value_sticky"))

                exp = store.getExperiment(forName: configKey, keepDeviceValue: false)
                expect(exp!.getValue(forKey: "key", defaultValue: "")).to(equal("value_new"))
            }

            it("does not migrate sticky values when user ID changes") {
                // set up deprecated cache
                let configKey = "config"
                let gateKey = "gate"
                let hashConfigKey = configKey.sha256()
                let hashGateKey = gateKey.sha256()
                let values: [String: [String: Any]] = [
                    "dynamic_configs": [
                        hashConfigKey: [
                            "rule_id": "default",
                            "value": ["key": "value"],
                            "is_user_in_experiment": true,
                            "is_experiment_active": true,
                        ],
                    ],
                    "feature_gates": [
                        hashGateKey: ["value": true, "rule_id": "rule_id_2"]
                    ]
                ]
                let stickyValues = [
                    hashConfigKey: [
                        "rule_id": "sticky",
                        "value": ["key": "value_sticky"],
                    ],
                ]
                UserDefaults.standard.setValue(values, forKey: InternalStore.DEPRECATED_localStorageKey)
                UserDefaults.standard.setValue("jkw", forKey: InternalStore.DEPRECATED_stickyUserIDKey)
                UserDefaults.standard.setValue(stickyValues, forKey: InternalStore.DEPRECATED_stickyUserExperimentsKey)

                let store = InternalStore(StatsigUser(userID: "not_jkw"))
                let exp = store.getExperiment(forName: configKey, keepDeviceValue: true)
                expect(exp!.getValue(forKey: "key", defaultValue: "")).to(equal("value"))
            }

            it("sets sticky experiment values correctly") {
                let store = InternalStore(StatsigUser())
                let configKey = "config"
                let hashConfigKey = configKey.sha256()

                let expKey = "exp"
                let hashedExpKey = expKey.sha256()

                let deviceExpKey = "device_exp"
                let hashedDeviceExpKey = deviceExpKey.sha256()

                let nonStickyExpKey = "exp_non_stick"
                let hashedNonStickyExpKey = nonStickyExpKey.sha256()

                var values: [String: [String: [String: Any]]] = [
                    "dynamic_configs": [
                        hashConfigKey: [
                            "rule_id": "default",
                            "value": ["key": "value"],
                        ],
                        hashedExpKey: [
                            "rule_id": "rule_id_1",
                            "value": ["label": "exp_v0"],
                            "is_device_based": false,
                            "is_user_in_experiment": true,
                            "is_experiment_active": true,
                        ],
                        hashedDeviceExpKey: [
                            "rule_id": "rule_id_1",
                            "value": ["label": "device_exp_v0"],
                            "is_device_based": true,
                            "is_user_in_experiment": true,
                            "is_experiment_active": true,
                        ],
                        hashedNonStickyExpKey: [
                            "rule_id": "rule_id_1",
                            "value": ["label": "non_stick_v0"],
                            "is_user_in_experiment": true,
                            "is_experiment_active": true,
                        ],
                    ],
                ]
                store.set(values: values)

                var exp = store.getExperiment(forName: expKey, keepDeviceValue: false)
                var deviceExp = store.getExperiment(forName: deviceExpKey, keepDeviceValue: false)
                var nonStickExp = store.getExperiment(forName: nonStickyExpKey, keepDeviceValue: false)
                expect(exp?.getValue(forKey: "label", defaultValue: "")).to(equal("exp_v0"))
                expect(deviceExp?.getValue(forKey: "label", defaultValue: "")).to(equal("device_exp_v0"))
                expect(nonStickExp?.getValue(forKey: "label", defaultValue: "")).to(equal("non_stick_v0"))

                // Change the values, now user should get updated values
                values["dynamic_configs"]![hashedExpKey]!["value"] = ["label": "exp_v1"]
                values["dynamic_configs"]![hashedDeviceExpKey]!["value"] = ["label": "device_exp_v1"]
                values["dynamic_configs"]![hashedNonStickyExpKey]!["value"] = ["label": "non_stick_v1"]
                store.set(values: values)

                exp = store.getExperiment(forName: expKey, keepDeviceValue: true)
                deviceExp = store.getExperiment(forName: deviceExpKey, keepDeviceValue: true)
                nonStickExp = store.getExperiment(forName: nonStickyExpKey, keepDeviceValue: false)
                expect(exp?.getValue(forKey: "label", defaultValue: "")).to(equal("exp_v1"))
                expect(deviceExp?.getValue(forKey: "label", defaultValue: "")).to(equal("device_exp_v1"))
                expect(nonStickExp?.getValue(forKey: "label", defaultValue: "")).to(equal("non_stick_v1"))

                // change the values again, but this time the value should be sticky from last time, except for the non sticky one
                values["dynamic_configs"]![hashedExpKey]!["value"] = ["label": "exp_v2"]
                values["dynamic_configs"]![hashedDeviceExpKey]!["value"] = ["label": "device_exp_v2"]
                values["dynamic_configs"]![hashedNonStickyExpKey]!["value"] = ["label": "non_stick_v2"]
                store.set(values: values)

                exp = store.getExperiment(forName: expKey, keepDeviceValue: true)
                deviceExp = store.getExperiment(forName: deviceExpKey, keepDeviceValue: true)
                nonStickExp = store.getExperiment(forName: nonStickyExpKey, keepDeviceValue: false)
                expect(exp?.getValue(forKey: "label", defaultValue: "")).to(equal("exp_v1"))
                expect(deviceExp?.getValue(forKey: "label", defaultValue: "")).to(equal("device_exp_v1"))
                expect(nonStickExp?.getValue(forKey: "label", defaultValue: "")).to(equal("non_stick_v2"))

                // Now we update the user to be no longer in the experiment, value should still be sticky
                values["dynamic_configs"]![hashedExpKey]!["value"] = ["label": "exp_v3"]
                values["dynamic_configs"]![hashedDeviceExpKey]!["value"] = ["label": "device_exp_v3"]
                values["dynamic_configs"]![hashedNonStickyExpKey]!["value"] = ["label": "non_stick_v3"]

                values["dynamic_configs"]![hashedExpKey]!["is_user_in_experiment"] = false
                values["dynamic_configs"]![hashedDeviceExpKey]!["is_user_in_experiment"] = false
                values["dynamic_configs"]![hashedNonStickyExpKey]!["is_user_in_experiment"] = false
                store.set(values: values)

                exp = store.getExperiment(forName: expKey, keepDeviceValue: true)
                deviceExp = store.getExperiment(forName: deviceExpKey, keepDeviceValue: true)
                nonStickExp = store.getExperiment(forName: nonStickyExpKey, keepDeviceValue: false)
                expect(exp?.getValue(forKey: "label", defaultValue: "")).to(equal("exp_v1"))
                expect(deviceExp?.getValue(forKey: "label", defaultValue: "")).to(equal("device_exp_v1"))
                expect(nonStickExp?.getValue(forKey: "label", defaultValue: "")).to(equal("non_stick_v3"))

                // Then we update the experiment to not be active, value should NOT be sticky
                values["dynamic_configs"]![hashedExpKey]!["value"] = ["label": "exp_v4"]
                values["dynamic_configs"]![hashedDeviceExpKey]!["value"] = ["label": "device_exp_v4"]
                values["dynamic_configs"]![hashedNonStickyExpKey]!["value"] = ["label": "non_stick_v4"]

                values["dynamic_configs"]![hashedExpKey]!["is_experiment_active"] = false
                values["dynamic_configs"]![hashedDeviceExpKey]!["is_experiment_active"] = false
                values["dynamic_configs"]![hashedNonStickyExpKey]!["is_experiment_active"] = false
                store.set(values: values)

                exp = store.getExperiment(forName: expKey, keepDeviceValue: true)
                deviceExp = store.getExperiment(forName: deviceExpKey, keepDeviceValue: true)
                nonStickExp = store.getExperiment(forName: nonStickyExpKey, keepDeviceValue: false)
                expect(exp?.getValue(forKey: "label", defaultValue: "")).to(equal("exp_v4"))
                expect(deviceExp?.getValue(forKey: "label", defaultValue: "")).to(equal("device_exp_v4"))
                expect(nonStickExp?.getValue(forKey: "label", defaultValue: "")).to(equal("non_stick_v4"))

                InternalStore.deleteAllLocalStorage()
            }

            it("it deletes user level sticky values but not device level sticky values when requested") {
                let store = InternalStore(StatsigUser(userID: "jkw"))
                let expKey = "exp"
                let hashedExpKey = expKey.sha256()

                let deviceExpKey = "device_exp"
                let hashedDeviceExpKey = deviceExpKey.sha256()

                var values: [String: [String: [String: Any]]] = [
                    "dynamic_configs": [
                        hashedExpKey: [
                            "rule_id": "rule_id_1",
                            "value": ["label": "exp_v0"],
                            "is_device_based": false,
                            "is_user_in_experiment": true,
                            "is_experiment_active": true,
                        ],
                        hashedDeviceExpKey: [
                            "rule_id": "rule_id_1",
                            "value": ["label": "device_exp_v0"],
                            "is_device_based": true,
                            "is_user_in_experiment": true,
                            "is_experiment_active": true,
                        ],
                    ],
                ]
                store.set(values: values)

                var exp = store.getExperiment(forName: expKey, keepDeviceValue: true)
                var deviceExp = store.getExperiment(forName: deviceExpKey, keepDeviceValue: true)
                expect(exp?.getValue(forKey: "label", defaultValue: "")).to(equal("exp_v0"))
                expect(deviceExp?.getValue(forKey: "label", defaultValue: "")).to(equal("device_exp_v0"))

                // Delete user sticky values (update user), change the latest values, now user should get updated values but device value stays the same
                store.updateUser(StatsigUser(userID: "tore"))
                values["dynamic_configs"]![hashedExpKey]!["value"] = ["label": "exp_v1"]
                values["dynamic_configs"]![hashedDeviceExpKey]!["value"] = ["label": "device_exp_v1"]
                store.set(values: values)

                exp = store.getExperiment(forName: expKey, keepDeviceValue: true)
                deviceExp = store.getExperiment(forName: deviceExpKey, keepDeviceValue: true)
                expect(exp?.getValue(forKey: "label", defaultValue: "")).to(equal("exp_v1"))
                expect(deviceExp?.getValue(forKey: "label", defaultValue: "")).to(equal("device_exp_v0"))

                // Try to get value with keepDeviceValue set to false. Should get updated values
                values["dynamic_configs"]![hashedExpKey]!["value"] = ["label": "exp_v2"]
                values["dynamic_configs"]![hashedDeviceExpKey]!["value"] = ["label": "device_exp_v2"]
                store.set(values: values)

                exp = store.getExperiment(forName: expKey, keepDeviceValue: false)
                deviceExp = store.getExperiment(forName: deviceExpKey, keepDeviceValue: false)
                expect(exp?.getValue(forKey: "label", defaultValue: "")).to(equal("exp_v2"))
                expect(deviceExp?.getValue(forKey: "label", defaultValue: "")).to(equal("device_exp_v2"))

                InternalStore.deleteAllLocalStorage()
            }

            it("changing userID in between sessions should invalidate sticky values") {
                var store = InternalStore(StatsigUser(userID: "jkw"))
                let expKey = "exp"
                let hashedExpKey = expKey.sha256()

                let deviceExpKey = "device_exp"
                let hashedDeviceExpKey = deviceExpKey.sha256()

                var values: [String: [String: [String: Any]]] = [
                    "dynamic_configs": [
                        hashedExpKey: [
                            "rule_id": "rule_id_1",
                            "value": ["label": "exp_v0"],
                            "is_device_based": false,
                            "is_user_in_experiment": true,
                            "is_experiment_active": true,
                        ],
                        hashedDeviceExpKey: [
                            "rule_id": "rule_id_1",
                            "value": ["label": "device_exp_v0"],
                            "is_device_based": true,
                            "is_user_in_experiment": true,
                            "is_experiment_active": true,
                        ],
                    ],
                ]
                waitUntil { done in
                    store.set(values: values) {
                        done()
                    }
                }

                var exp = store.getExperiment(forName: expKey, keepDeviceValue: true)
                var deviceExp = store.getExperiment(forName: deviceExpKey, keepDeviceValue: true)
                expect(exp?.getValue(forKey: "label", defaultValue: "")).to(equal("exp_v0"))
                expect(deviceExp?.getValue(forKey: "label", defaultValue: "")).to(equal("device_exp_v0"))

                // Reinitialize, same user ID, should keep sticky values
                store = InternalStore(StatsigUser(userID: "jkw"))
                values["dynamic_configs"]![hashedExpKey]!["value"] = ["label": "exp_v1"] // this value changed, but old value should be sticky
                values["dynamic_configs"]![hashedDeviceExpKey]!["value"] = ["label": "device_exp_v1"]
                waitUntil { done in
                    store.set(values: values) {
                        done()
                    }
                }
                exp = store.getExperiment(forName: expKey, keepDeviceValue: true)
                deviceExp = store.getExperiment(forName: deviceExpKey, keepDeviceValue: true)
                expect(exp?.getValue(forKey: "label", defaultValue: "")).to(equal("exp_v0")) // should still get old value
                expect(deviceExp?.getValue(forKey: "label", defaultValue: "")).to(equal("device_exp_v0"))


                // Re-initialize store with a different ID, change the latest values, now user should get updated values but device value stays the same
                store = InternalStore(StatsigUser(userID: "tore"))
                values["dynamic_configs"]![hashedExpKey]!["value"] = ["label": "exp_v1"]
                values["dynamic_configs"]![hashedDeviceExpKey]!["value"] = ["label": "device_exp_v1"]
                waitUntil { done in
                    store.set(values: values) {
                        done()
                    }
                }

                exp = store.getExperiment(forName: expKey, keepDeviceValue: true)
                deviceExp = store.getExperiment(forName: deviceExpKey, keepDeviceValue: true)
                expect(exp?.getValue(forKey: "label", defaultValue: "")).to(equal("exp_v1"))
                expect(deviceExp?.getValue(forKey: "label", defaultValue: "")).to(equal("device_exp_v0"))

                // Try to get value with keepDeviceValue set to false. Should get updated values
                values["dynamic_configs"]![hashedExpKey]!["value"] = ["label": "exp_v2"]
                values["dynamic_configs"]![hashedDeviceExpKey]!["value"] = ["label": "device_exp_v2"]
                waitUntil { done in
                    store.set(values: values) {
                        done()
                    }
                }

                exp = store.getExperiment(forName: expKey, keepDeviceValue: false)
                deviceExp = store.getExperiment(forName: deviceExpKey, keepDeviceValue: false)
                expect(exp?.getValue(forKey: "label", defaultValue: "")).to(equal("exp_v2"))
                expect(deviceExp?.getValue(forKey: "label", defaultValue: "")).to(equal("device_exp_v2"))

                // update user ID back, should get old values
                store.updateUser(StatsigUser(userID: "jkw"))
                exp = store.getExperiment(forName: expKey, keepDeviceValue: true)
                expect(exp?.getValue(forKey: "label", defaultValue: "")).to(equal("exp_v0"))

                // reset sticky exp
                exp = store.getExperiment(forName: expKey, keepDeviceValue: false)
                expect(exp?.getValue(forKey: "label", defaultValue: "")).to(equal("exp_v1"))

                // add a custom ID, now should get default value because cache key is different
                store.updateUser(StatsigUser(userID: "jkw", customIDs: ["id_type_1": "123456"]))
                exp = store.getExperiment(forName: expKey, keepDeviceValue: false)
                expect(exp).to(beNil())

                InternalStore.deleteAllLocalStorage()
            }

            it("migrates non serialized caches") {
                let expKey = "exp"
                let hashedExpKey = expKey.sha256()

                let stickyExpKey = "sticky_exp"
                let hashedStickyExpKey = stickyExpKey.sha256()

                let cacheByID: [String: Any] = [
                    "jkw": [
                        "dynamic_configs": [
                            hashedExpKey: [
                                "rule_id": "rule_id_1",
                                "value": ["label": "exp_v0"],
                                "is_device_based": false,
                                "is_user_in_experiment": true,
                                "is_experiment_active": true,
                            ],
                        ],
                        "sticky_experiments": [:],
                        "time": 0
                    ]
                ]

                let stickyDeviceExperiments: [String: Any] = [
                    hashedStickyExpKey: [
                        "value":
                            ["label": "device_exp_v0"]
                        ,
                        "is_experiment_active": true,
                        "is_device_based": true,
                        "is_user_in_experiment": true,
                        "rule_id": "rule_id_1"
                    ]
                ]

                // Save a value in the deprecated style
                UserDefaults.standard.setValue(cacheByID, forKey: InternalStore.localStorageKey)
                UserDefaults.standard.setValue(stickyDeviceExperiments, forKey: InternalStore.stickyDeviceExperimentsKey)
                UserDefaults.standard.synchronize()

                let store = InternalStore(StatsigUser(userID: "jkw"))
                let config = store.getConfig(forName:expKey)
                let val = config?.getValue(forKey: "label", defaultValue: "invalid")
                expect(val).to(equal("exp_v0"))

                let stickyConfig = store.getExperiment(forName: stickyExpKey, keepDeviceValue: true)
                let stickyVal = stickyConfig?.getValue(forKey: "label", defaultValue: "invalid")
                expect(stickyVal).to(equal("device_exp_v0"))
            }
        }
    }
}
