/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import OpenTelemetryApi

class CounterMetricSdkBase<T>: CounterMetric {
  // Вместо Lock используем последовательную очередь
  let queue = DispatchQueue(label: "com.example.CounterMetricSdkBase.queue")
  public private(set) var boundInstruments = [LabelSet: BoundCounterMetricSdkBase<T>]()
  let metricName: String

  init(name: String) {
    metricName = name
  }

  func add(value: T, labelset: LabelSet) {
    fatalError()
  }

  func add(value: T, labels: [String: String]) {
    fatalError()
  }

  func bind(labelset: LabelSet) -> BoundCounterMetric<T> {
    return bind(labelset: labelset, isShortLived: false)
  }

  func bind(labels: [String: String]) -> BoundCounterMetric<T> {
    return bind(labelset: LabelSet(labels: labels), isShortLived: false)
  }

  internal func bind(labelset: LabelSet, isShortLived: Bool) -> BoundCounterMetric<T> {
    // Выполняем потокобезопасный доступ к boundInstruments через queue.sync
    let boundInstrument: BoundCounterMetricSdkBase<T> = queue.sync {
      if let existing = boundInstruments[labelset] {
        return existing
      } else {
        let status = isShortLived ? RecordStatus.updatePending : RecordStatus.bound
        let newInstrument = createMetric(recordStatus: status)
        boundInstruments[labelset] = newInstrument
        return newInstrument
      }
    }

    // Предполагается, что BoundCounterMetricSdkBase<T> также переведен на использование DispatchQueue и имеет метод syncStatus
    boundInstrument.syncStatus {
      switch boundInstrument.status {
      case .noPendingUpdate:
        boundInstrument.status = .updatePending
      case .candidateForRemoval:
        // Если инструмент кандидат на удаление, возвращаем его обратно
        queue.sync {
          boundInstrument.status = .updatePending

          if boundInstruments[labelset] == nil {
            boundInstruments[labelset] = boundInstrument
          }
        }
      case .bound, .updatePending:
        break
      }
    }

    return boundInstrument
  }

  internal func unBind(labelSet: LabelSet) {
    queue.sync {
      if let boundInstrument = boundInstruments[labelSet] {
        boundInstrument.syncStatus {
          if boundInstrument.status == .candidateForRemoval {
            boundInstruments[labelSet] = nil
          }
        }
      }
    }
  }

  func createMetric(recordStatus: RecordStatus) -> BoundCounterMetricSdkBase<T> {
    fatalError("Must be implemented in subclass")
  }
}
