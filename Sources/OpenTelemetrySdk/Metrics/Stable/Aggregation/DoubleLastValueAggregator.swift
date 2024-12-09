//
// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import OpenTelemetryApi

public class DoubleLastValueAggregator: StableAggregator {
  private var reservoirSupplier: () -> ExemplarReservoir

  internal init(reservoirSupplier: @escaping () -> ExemplarReservoir) {
    self.reservoirSupplier = reservoirSupplier
  }

  public func diff(previousCumulative: PointData, currentCumulative: PointData) throws -> PointData {
    currentCumulative
  }

  public func toPoint(measurement: Measurement) throws -> PointData {
    DoublePointData(
      startEpochNanos: measurement.startEpochNano,
      endEpochNanos: measurement.epochNano,
      attributes: measurement.attributes,
      exemplars: [],
      value: measurement.doubleValue
    )
  }

  public func createHandle() -> AggregatorHandle {
    Handle(exemplarReservoir: reservoirSupplier())
  }

  public func toMetricData(resource: Resource,
                           scope: InstrumentationScopeInfo,
                           descriptor: MetricDescriptor,
                           points: [PointData],
                           temporality: AggregationTemporality) -> StableMetricData {
    StableMetricData.createDoubleGauge(
      resource: resource,
      instrumentationScopeInfo: scope,
      name: descriptor.name,
      description: descriptor.description,
      unit: descriptor.instrument.unit,
      data: StableGaugeData(aggregationTemporality: temporality, points: points)
    )
  }

  private class Handle: AggregatorHandle {
    private var value: Double = 0
    // Используем последовательную очередь вместо Lock
    private let queue = DispatchQueue(label: "com.example.DoubleLastValueAggregator.Handle")

    override init(exemplarReservoir: ExemplarReservoir) {
      super.init(exemplarReservoir: exemplarReservoir)
    }

    override func doAggregateThenMaybeReset(startEpochNano: UInt64,
                                            endEpochNano: UInt64,
                                            attributes: [String: AttributeValue],
                                            exemplars: [ExemplarData],
                                            reset: Bool) -> PointData {
      return queue.sync {
        let currentValue = value
        if reset {
          value = 0
        }
        return DoublePointData(
          startEpochNanos: startEpochNano,
          endEpochNanos: endEpochNano,
          attributes: attributes,
          exemplars: exemplars,
          value: currentValue
        )
      }
    }

    override func doRecordDouble(value: Double) {
      queue.sync {
        self.value = value
      }
    }
  }
}
