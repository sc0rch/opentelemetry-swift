//
// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import OpenTelemetryApi

public class DoubleSumAggregator: SumAggregator, StableAggregator {
  private let reservoirSupplier: () -> ExemplarReservoir

  public func diff(previousCumulative: PointData, currentCumulative: PointData) throws -> PointData {
    // Предполагается, что реализация оператора '-' у PointData корректно работает.
    // Если у вас нет такого оператора, нужно самостоятельно реализовать логику вычитания.
    currentCumulative - previousCumulative
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
    StableMetricData.createDoubleSum(
      resource: resource,
      instrumentationScopeInfo: scope,
      name: descriptor.instrument.name,
      description: descriptor.instrument.description,
      unit: descriptor.instrument.unit,
      isMonotonic: self.isMonotonic,
      data: StableSumData(aggregationTemporality: temporality, points: points as! [DoublePointData])
    )
  }

  init(instrumentDescriptor: InstrumentDescriptor, reservoirSupplier: @escaping () -> ExemplarReservoir) {
    self.reservoirSupplier = reservoirSupplier
    super.init(instrumentDescriptor: instrumentDescriptor)
  }

  private class Handle: AggregatorHandle {
    private var sum: Double = 0
    // Вместо Lock используем serial очередь.
    private let queue = DispatchQueue(label: "com.example.DoubleSumAggregator.Handle")

    override init(exemplarReservoir: ExemplarReservoir) {
      super.init(exemplarReservoir: exemplarReservoir)
    }

    override func doAggregateThenMaybeReset(startEpochNano: UInt64,
                                            endEpochNano: UInt64,
                                            attributes: [String: AttributeValue],
                                            exemplars: [ExemplarData],
                                            reset: Bool) -> PointData {
      return queue.sync {
        let currentValue = sum
        if reset {
          sum = 0
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
        sum += value
      }
    }
  }
}
