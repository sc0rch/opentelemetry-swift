/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

/// Basic aggregator which calculates a Sum from individual measurements.
public class CounterSumAggregator<T: SignedNumeric>: Aggregator<T> {
  private var sum: T = 0
  private var pointCheck: T = 0
  private let queue = DispatchQueue(label: "com.example.CounterSumAggregator.queue")

  public override func update(value: T) {
    queue.sync {
      sum += value
    }
  }

  public override func checkpoint() {
    queue.sync {
      super.checkpoint()
      pointCheck = sum
      sum = 0
    }
  }

  public override func toMetricData() -> MetricData {
    return queue.sync {
      SumData<T>(startTimestamp: lastStart, timestamp: lastEnd, sum: pointCheck)
    }
  }

  public override func getAggregationType() -> AggregationType {
    if T.self == Double.Type.self {
      return .doubleSum
    } else {
      return .intSum
    }
  }
}
