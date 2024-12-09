/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

public class MetricProcessorSdk: MetricProcessor {
  // Используем последовательную очередь для потокобезопасного доступа к metrics
  private let queue = DispatchQueue(label: "com.example.MetricProcessorSdk.queue")
  var metrics: [Metric]

  public init() {
    metrics = [Metric]()
  }

  /// Завершает текущий цикл сбора и возвращает метрики этого цикла.
  /// После возвращения метрик массив очищается.
  public func finishCollectionCycle() -> [Metric] {
    return queue.sync {
      let currentMetrics = metrics
      metrics = []
      return currentMetrics
    }
  }

  /// Обрабатываем метрику - добавляем её в список.
  public func process(metric: Metric) {
    queue.sync {
      metrics.append(metric)
    }
  }
}
