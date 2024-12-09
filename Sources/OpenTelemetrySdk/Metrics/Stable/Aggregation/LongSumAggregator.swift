//
// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import OpenTelemetryApi

public class LongSumAggregator: SumAggregator, StableAggregator {
    private let reservoirSupplier: () -> ExemplarReservoir

    init(descriptor: InstrumentDescriptor, reservoirSupplier: @escaping () -> ExemplarReservoir) {
        self.reservoirSupplier = reservoirSupplier
        super.init(instrumentDescriptor: descriptor)
    }
    
    public func diff(previousCumulative: PointData, currentCumulative: PointData) throws -> PointData {
        return currentCumulative - previousCumulative
    }
    
    public func toPoint(measurement: Measurement) throws -> PointData {
        LongPointData(
            startEpochNanos: measurement.startEpochNano,
            endEpochNanos: measurement.epochNano,
            attributes: measurement.attributes,
            exemplars: [ExemplarData](),
            value: measurement.longValue
        )
    }
    
    public func createHandle() -> AggregatorHandle {
        return Handle(exemplarReservoir: reservoirSupplier())
    }
    
    public func toMetricData(
        resource: Resource,
        scope: InstrumentationScopeInfo,
        descriptor: MetricDescriptor,
        points: [PointData],
        temporality: AggregationTemporality
    ) -> StableMetricData {
        StableMetricData.createLongSum(
            resource: resource,
            instrumentationScopeInfo: scope,
            name: descriptor.instrument.name,
            description: descriptor.instrument.description,
            unit: descriptor.instrument.unit,
            isMonotonic: self.isMonotonic,
            data: StableSumData(
                aggregationTemporality: temporality,
                points: points as! [LongPointData]
            )
        )
    }
    
    private class Handle: AggregatorHandle {
        // Вместо Lock используем очередь для потокобезопасного доступа к sum
        private let sumQueue = DispatchQueue(label: "com.example.LongSumAggregator.Handle")
        private var _sum: Int = 0
        
        override func doAggregateThenMaybeReset(
            startEpochNano: UInt64,
            endEpochNano: UInt64,
            attributes: [String: AttributeValue],
            exemplars: [ExemplarData],
            reset: Bool
        ) -> PointData {
            var value = 0
            sumQueue.sync {
                value = _sum
                if reset {
                    _sum = 0
                }
            }
            return LongPointData(
                startEpochNanos: startEpochNano,
                endEpochNanos: endEpochNano,
                attributes: attributes,
                exemplars: exemplars,
                value: value
            )
        }
        
        override func doRecordLong(value: Int) {
            sumQueue.sync {
                _sum += value
            }
        }
    }
}
