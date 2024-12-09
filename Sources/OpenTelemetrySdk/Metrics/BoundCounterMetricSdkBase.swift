/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import OpenTelemetryApi

class BoundCounterMetricSdkBase<T>: BoundCounterMetric<T> {
  internal var status: RecordStatus
  // Заменяем Lock на последовательную очередь
  private let statusQueue = DispatchQueue(label: "com.example.BoundCounterMetricSdkBase.statusQueue")

  init(recordStatus: RecordStatus) {
    status = recordStatus
    super.init()
  }

  func getAggregator() -> Aggregator<T> {
    fatalError("Must be implemented in subclass")
  }

  // Новый метод для потокобезопасного доступа к status
  func syncStatus(_ block: () -> Void) {
    statusQueue.sync {
      block()
    }
  }
}
