/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */


import Foundation

class BoundRawHistogramMetricSdk<T>: BoundRawHistogramMetricSdkBase<T> {
  private var metricData = [MetricData]()
  private var metricDataCheckpoint = [MetricData]()
  // Заменяем Lock на сериализованную очередь
  private let queue = DispatchQueue(label: "com.example.BoundRawHistogramMetricSdk.queue")

  override init(recordStatus: RecordStatus) {
    super.init(recordStatus: recordStatus)
  }

  override func record(explicitBoundaries: [T], counts: [Int], startDate: Date, endDate: Date, count: Int, sum: T) {
    queue.sync {
      metricData.append(
        HistogramData<T>(
          startTimestamp: startDate,
          timestamp: endDate,
          buckets: (boundaries: explicitBoundaries, counts: counts),
          count: count,
          sum: sum
        )
      )
    }
  }

  override func checkpoint() {
    queue.sync {
      metricDataCheckpoint = metricData
      metricData = []
    }
  }

  override func getMetrics() -> [MetricData] {
    return queue.sync { metricDataCheckpoint }
  }
}
