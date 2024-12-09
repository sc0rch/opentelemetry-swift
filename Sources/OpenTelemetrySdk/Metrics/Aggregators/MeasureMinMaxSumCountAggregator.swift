/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

/// Aggregator which calculates summary (Min,Max,Sum,Count) from measures.
public class MeasureMinMaxSumCountAggregator<T: SignedNumeric & Comparable>: Aggregator<T> {
  fileprivate var summary = Summary<T>()
  fileprivate var pointCheck = Summary<T>()

  // Заменяем Lock на последовательную очередь.
  private let queue = DispatchQueue(label: "com.example.MeasureMinMaxSumCountAggregator.queue")

  override public func update(value: T) {
    queue.sync {
      self.summary.count += 1
      self.summary.sum += value
      self.summary.max = (self.summary.max != nil) ? max(self.summary.max, value) : value
      self.summary.min = (self.summary.min != nil) ? min(self.summary.min, value) : value
    }
  }

  override public func checkpoint() {
    queue.sync {
      super.checkpoint()
      pointCheck = summary
      summary = Summary<T>()
    }
  }

  public override func toMetricData() -> MetricData {
    return queue.sync {
      SummaryData<T>(
        startTimestamp: lastStart,
        timestamp: lastEnd,
        count: pointCheck.count,
        sum: pointCheck.sum,
        min: pointCheck.min ?? 0,
        max: pointCheck.max ?? 0
      )
    }
  }

  public override func getAggregationType() -> AggregationType {
    // Этот метод не меняет состояние, поэтому синхронизация не обязательна.
    // Но если вы хотите перестраховаться, можете обернуть в queue.sync.
    if T.self == Double.Type.self {
      return .doubleSummary
    } else {
      return .intSummary
    }
  }
}

private struct Summary<T> where T: SignedNumeric {
  var sum: T
  var count: Int
  var min: T!
  var max: T!
  init() {
    sum = 0
    count = 0
  }
}
