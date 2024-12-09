/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import OpenTelemetryApi

class BoundRawCounterMetricSdk<T: SignedNumeric> : BoundRawCounterMetricSdkBase<T> {
  private var metricData = [MetricData]()
  private var metricDataCheckpoint = [MetricData]()
  private let queue = DispatchQueue(label: "BoundRawCounterMetricSdk.queue")

  override init(recordStatus: RecordStatus) {
    super.init(recordStatus: recordStatus)
  }

  override func record(sum: T, startDate: Date, endDate: Date) {
    queue.sync {
      metricData.append(SumData<T>(startTimestamp: startDate, timestamp: endDate, sum: sum))
    }
  }

  override func checkpoint() {
    queue.sync {
      metricDataCheckpoint = metricData
      metricData = []
    }
  }

  override func getMetrics() -> [MetricData] {
    return queue.sync {
      metricDataCheckpoint
    }
  }
}
