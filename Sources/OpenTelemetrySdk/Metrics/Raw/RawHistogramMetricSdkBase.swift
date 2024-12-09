/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import OpenTelemetryApi

class RawHistogramMetricSdkBase<T> : RawHistogramMetric {
  // Вместо Lock используем очередь
  let queue = DispatchQueue(label: "com.example.RawHistogramMetricSdkBase.queue")

  public private(set) var boundInstruments = [LabelSet: BoundRawHistogramMetricSdkBase<T>]()
  let metricName : String

  init(name: String) {
    metricName = name
  }

  func record(explicitBoundaries: Array<T>,
              counts: Array<Int>,
              startDate: Date,
              endDate: Date,
              count: Int,
              sum: T,
              labelset: LabelSet) {
    // noop
  }

  func record(explicitBoundaries: Array<T>,
              counts: Array<Int>,
              startDate: Date,
              endDate: Date,
              count: Int,
              sum: T,
              labels: [String : String]) {
    // noop
  }

  func bind(labelset: LabelSet) -> BoundRawHistogramMetric<T> {
    bind(labelset: labelset, isShortLived: false)
  }

  func bind(labels: [String : String]) -> BoundRawHistogramMetric<T> {
    bind(labelset: LabelSet(labels: labels), isShortLived: false)
  }

  internal func bind(labelset: LabelSet, isShortLived: Bool) -> BoundRawHistogramMetric<T> {
    // Выполняем операции в serial-очереди
    let boundInstrument: BoundRawHistogramMetricSdkBase<T> = queue.sync {
      if let existing = boundInstruments[labelset] {
        return existing
      } else {
        let status = isShortLived ? RecordStatus.updatePending : RecordStatus.bound
        let newInstrument = createMetric(recordStatus: status)
        boundInstruments[labelset] = newInstrument
        return newInstrument
      }
    }

    boundInstrument.syncStatus {
      switch boundInstrument.status {
      case .noPendingUpdate:
        boundInstrument.status = .updatePending
      case .candidateForRemoval:
        // Если инструмент был кандидатом на удаление, нужно вернуть его обратно
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

  func createMetric(recordStatus: RecordStatus) -> BoundRawHistogramMetricSdkBase<T> {
    fatalError("Must be implemented by subclass")
  }
}
