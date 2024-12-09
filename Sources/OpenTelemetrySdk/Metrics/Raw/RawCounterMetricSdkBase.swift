/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import OpenTelemetryApi

class RawCounterMetricSdkBase<T> : RawCounterMetric {
  // Вместо Lock используется последовательная очередь
  private let queue = DispatchQueue(label: "com.example.RawCounterMetricSdkBase.queue")

  // Доступ к boundInstruments только через queue.sync
  private var _boundInstruments = [LabelSet: BoundRawCounterMetricSdkBase<T>]()
  public private(set) var boundInstruments: [LabelSet: BoundRawCounterMetricSdkBase<T>] {
    get {
      return queue.sync { _boundInstruments }
    }
    set {
      queue.sync { _boundInstruments = newValue }
    }
  }

  let metricName : String

  init(name: String) {
    metricName = name
  }

  func record(sum: T, startDate: Date, endDate: Date, labels: [String : String]) {
    // noop
  }

  func record(sum: T, startDate: Date, endDate: Date, labelset: LabelSet) {
    // noop
  }

  func bind(labelset: LabelSet) -> BoundRawCounterMetric<T> {
    return bind(labelset: labelset, isShortLived: false)
  }

  internal func bind(labelset: LabelSet, isShortLived: Bool) -> BoundRawCounterMetric<T> {
    // Используем очередь для потокобезопасного доступа к boundInstruments
    let boundInstrument: BoundRawCounterMetricSdkBase<T> = queue.sync {
      if let existing = _boundInstruments[labelset] {
        return existing
      } else {
        let status = isShortLived ? RecordStatus.updatePending : RecordStatus.bound
        let newInstrument = createMetric(recordStatus: status)
        _boundInstruments[labelset] = newInstrument
        return newInstrument
      }
    }

    // Обновляем статус инструмента под защитой его собственного statusLock
    boundInstrument.syncStatus {
      switch boundInstrument.status {
      case .noPendingUpdate:
        boundInstrument.status = .updatePending
      case .candidateForRemoval:
        // Если инструмент помечен для удаления, нужно убедиться, что он снова в словаре
        // и обновить статус.
        queue.sync {
          boundInstrument.status = .updatePending
          if _boundInstruments[labelset] == nil {
            _boundInstruments[labelset] = boundInstrument
          }
        }
      case .bound, .updatePending:
        break
      }
    }

    return boundInstrument
  }

  func bind(labels: [String : String]) -> BoundRawCounterMetric<T> {
    return bind(labelset: LabelSet(labels: labels), isShortLived: false)
  }

  internal func unBind(labelSet: LabelSet) {
    queue.sync {
      guard let boundInstrument = _boundInstruments[labelSet] else { return }
      boundInstrument.syncStatus {
        if boundInstrument.status == .candidateForRemoval {
          _boundInstruments[labelSet] = nil
        }
      }
    }
  }

  func createMetric(recordStatus: RecordStatus) -> BoundRawCounterMetricSdkBase<T> {
    // noop
    fatalError()
  }
}
