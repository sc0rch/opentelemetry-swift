/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

/// Aggregator which calculates histogram (bucket distribution, sum, count) from measures.
public class HistogramAggregator<T: SignedNumeric & Comparable>: Aggregator<T> {
  fileprivate var histogram: Histogram<T>
  fileprivate var pointCheck: Histogram<T>
  fileprivate var boundaries: Array<T>

  // Вместо Lock используем serial DispatchQueue
  private let queue = DispatchQueue(label: "com.example.HistogramAggregator.queue")

  private let defaultBoundaries: Array<T> = [5, 10, 25, 50, 75, 100, 250, 500, 750, 1_000, 2_500, 5_000, 7_500,
                                             10_000]

  public init(explicitBoundaries: Array<T>? = nil) throws {
    if let explicitBoundaries = explicitBoundaries, !explicitBoundaries.isEmpty {
      self.boundaries = explicitBoundaries.sorted { $0 < $1 }
    } else {
      self.boundaries = defaultBoundaries
    }

    self.histogram = Histogram<T>(boundaries: self.boundaries)
    self.pointCheck = Histogram<T>(boundaries: self.boundaries)
  }

  override public func update(value: T) {
    queue.sync {
      histogram.count += 1
      histogram.sum += value

      for i in 0..<boundaries.count {
        if value < boundaries[i] {
          histogram.buckets.counts[i] += 1
          return
        }
      }
      // value is above all observed boundaries
      histogram.buckets.counts[boundaries.count] += 1
    }
  }

  override public func checkpoint() {
    queue.sync {
      super.checkpoint()
      pointCheck = histogram
      histogram = Histogram<T>(boundaries: self.boundaries)
    }
  }

  public override func toMetricData() -> MetricData {
    return queue.sync {
      HistogramData<T>(
        startTimestamp: lastStart,
        timestamp: lastEnd,
        buckets: pointCheck.buckets,
        count: pointCheck.count,
        sum: pointCheck.sum
      )
    }
  }

  public override func getAggregationType() -> AggregationType {
    // Данный метод не модифицирует состояние, поэтому его не обязательно помещать в очередь
    if T.self == Double.Type.self {
      return .doubleHistogram
    } else {
      return .intHistogram
    }
  }
}

private struct Histogram<T> where T: SignedNumeric {
  var buckets: (
    boundaries: Array<T>,
    counts: Array<Int>
  )
  var sum: T
  var count: Int

  init(boundaries: Array<T>) {
    sum = 0
    count = 0
    buckets = (
      boundaries: boundaries,
      counts: Array(repeating: 0, count: boundaries.count + 1)
    )
  }
}
