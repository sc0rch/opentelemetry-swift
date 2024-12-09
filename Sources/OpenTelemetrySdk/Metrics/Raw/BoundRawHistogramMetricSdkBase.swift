/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */


import Foundation
import OpenTelemetryApi

class BoundRawHistogramMetricSdkBase<T> : BoundRawHistogramMetric<T> {
  internal var status: RecordStatus
  // Заменяем Lock на очередь
  private let statusQueue = DispatchQueue(label: "com.example.BoundRawHistogramMetricSdkBase.statusQueue")

  init(recordStatus: RecordStatus) {
    status = recordStatus
    super.init()
  }

  func checkpoint() {
    // noop или ваша логика
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
