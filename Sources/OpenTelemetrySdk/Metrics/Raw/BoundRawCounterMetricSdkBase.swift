/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */


import Foundation
import OpenTelemetryApi

class BoundRawCounterMetricSdkBase<T>: BoundRawCounterMetric<T> {
  internal var status : RecordStatus
  // Заменяем Lock на очередь
  private let statusQueue = DispatchQueue(label: "com.example.BoundRawCounterMetricSdkBase.statusQueue")

  init(recordStatus: RecordStatus) {
    status = recordStatus
    super.init()
  }

  func checkpoint() {
  }

  func getMetrics() -> [MetricData] {
    fatalError()
  }

  func syncStatus(_ block: () -> Void) {
    statusQueue.sync {
      block()
    }
  }
}
