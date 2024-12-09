/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

public class MaxValueAggregator<T: SignedNumeric & Comparable>: Aggregator<T> {
  private var value: T = 0
  private var pointCheck: T = 0

  // Заменяем Lock на последовательную очередь
  private let queue = DispatchQueue(label: "com.example.MaxValueAggregator.queue")

  override public func update(value: T) {
    queue.sync {
      if value > self.value {
        self.value = value
      }
    }
  }

  override public func checkpoint() {
    queue.sync {
      super.checkpoint()
      self.pointCheck = self.value
      self.value = 0
    }
  }

  override public func toMetricData() -> MetricData {
    queue.sync {
      return SumData<T>(startTimestamp: lastStart, timestamp: lastEnd, sum: pointCheck)
    }
  }

  override public func getAggregationType() -> AggregationType {
    // Эта функция не работает с изменяемыми данными,
    // поэтому можно оставить без синхронизации
    if T.self == Double.Type.self {
      return .doubleGauge
    } else {
      return .intGauge
    }
  }
}
