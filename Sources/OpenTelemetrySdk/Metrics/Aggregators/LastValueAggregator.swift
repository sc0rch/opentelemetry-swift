/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

/// Simple aggregator that only keeps the last value.
public class LastValueAggregator<T: SignedNumeric>: Aggregator<T> {
  private var value: T = 0
  private var pointCheck: T = 0
  private let queue = DispatchQueue(label: "com.example.LastValueAggregator")

  public override func update(value: T) {
    queue.sync {
      self.value = value
    }
  }

  public override func checkpoint() {
    queue.sync {
      super.checkpoint()
      self.pointCheck = self.value
    }
  }

  public override func toMetricData() -> MetricData {
    // Чтение pointCheck также в синхронной очереди для гарантии консистентности.
    let currentPointCheck = queue.sync { pointCheck }

    return SumData<T>(
      startTimestamp: lastStart,
      timestamp: lastEnd,
      sum: currentPointCheck
    )
  }

  public override func getAggregationType() -> AggregationType {
    if T.self == Double.Type.self {
      return .doubleSum
    } else {
      return .intSum
    }
  }
}
