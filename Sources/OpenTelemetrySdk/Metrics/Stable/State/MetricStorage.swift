//
// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0
// 

import Foundation
import OpenTelemetryApi

public struct MetricStorageConstants {
    static let MAX_CARDINALITY = 2_000
}

public protocol MetricStorage: AnyObject {
    var metricDescriptor : MetricDescriptor { get }
    func collect(resource : Resource, scope : InstrumentationScopeInfo, startEpochNanos: UInt64, epochNanos : UInt64) -> StableMetricData
    func isEmpty() -> Bool
}

public protocol WritableMetricStorage {
    mutating func recordLong(value: Int, attributes: [String: AttributeValue])
    mutating func recordDouble(value: Double, attributes: [String: AttributeValue])
}
