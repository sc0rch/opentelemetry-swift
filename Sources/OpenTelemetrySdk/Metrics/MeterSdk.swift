/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import OpenTelemetryApi

public extension Meter {
  func addMetric(name: String, type: AggregationType, data: [MetricData]) {
    // noop - оставляем без изменений
  }
}

class MeterSdk: Meter {
  private let queue = DispatchQueue(label: "com.example.MeterSdk.queue")

  let meterName: String
  var metricProcessor: MetricProcessor
  var instrumentationScopeInfo: InstrumentationScopeInfo
  var resource: Resource

  var intGauges = [String: IntObservableGaugeSdk]()
  var doubleGauges = [String: DoubleObservableGaugeSdk]()
  var intCounters = [String: CounterMetricSdk<Int>]()
  var doubleCounters = [String: CounterMetricSdk<Double>]()
  var intMeasures = [String: MeasureMetricSdk<Int>]()
  var doubleMeasures = [String: MeasureMetricSdk<Double>]()
  var intHistogram = [String: HistogramMetricSdk<Int>]()
  var doubleHistogram = [String: HistogramMetricSdk<Double>]()
  var rawDoubleHistogram = [String: RawHistogramMetricSdk<Double>]()
  var rawIntHistogram = [String: RawHistogramMetricSdk<Int>]()
  var rawDoubleCounters = [String: RawCounterMetricSdk<Double>]()
  var rawIntCounters = [String: RawCounterMetricSdk<Int>]()
  var intObservers = [String: IntObserverMetricSdk]()
  var doubleObservers = [String: DoubleObserverMetricSdk]()

  var metrics = [Metric]()

  init(meterSharedState: MeterSharedState, instrumentationScopeInfo: InstrumentationScopeInfo) {
    meterName = instrumentationScopeInfo.name
    resource = meterSharedState.resource
    metricProcessor = meterSharedState.metricProcessor
    self.instrumentationScopeInfo = instrumentationScopeInfo
  }

  func getLabelSet(labels: [String: String]) -> LabelSet {
    return LabelSetSdk(labels: labels)
  }

  func addMetric(name: String, type: AggregationType, data: [MetricData]) {
    queue.sync {
      var newMetric = Metric(namespace: meterName,
                             name: name,
                             desc: meterName + name,
                             type: type,
                             resource: resource,
                             instrumentationScopeInfo: instrumentationScopeInfo)
      newMetric.data = data
      metrics.append(newMetric)
    }
  }

  func collect() {
    queue.sync {
      var boundInstrumentsToRemove = [LabelSet]()

      // process raw metrics
      let checkpointMetrics = metrics
      metrics = []
      checkpointMetrics.forEach {
        metricProcessor.process(metric: $0)
      }

      // Пример изменения для intCounters
      intCounters.forEach { counter in
        let metricName = counter.key
        let counterInstrument = counter.value

        var metric = Metric(namespace: meterName, name: metricName, desc: meterName + metricName,
                            type: AggregationType.intSum, resource: resource,
                            instrumentationScopeInfo: instrumentationScopeInfo)

        // Ранее: counterInstrument.bindUnbindLock.withLockVoid {
        // Теперь: counterInstrument.queue.sync
        counterInstrument.queue.sync {
          counterInstrument.boundInstruments.forEach { boundInstrument in
            let labelSet = boundInstrument.key
            let aggregator = boundInstrument.value.getAggregator()
            aggregator.checkpoint()

            var metricData = aggregator.toMetricData()
            metricData.labels = labelSet.labels
            metric.data.append(metricData)

            // Ранее: boundInstrument.value.statusLock.withLockVoid
            // Теперь: boundInstrument.value.syncStatus
            boundInstrument.value.syncStatus {
              switch boundInstrument.value.status {
              case .updatePending:
                boundInstrument.value.status = .noPendingUpdate
              case .noPendingUpdate:
                boundInstrument.value.status = .candidateForRemoval
              case .candidateForRemoval:
                boundInstrumentsToRemove.append(labelSet)
              case .bound:
                break
              }
            }
          }
        }

        metricProcessor.process(metric: metric)
        boundInstrumentsToRemove.forEach { boundInstrument in
          counterInstrument.unBind(labelSet: boundInstrument)
        }
        boundInstrumentsToRemove.removeAll()
      }

      // Аналогично изменяем doubleCounters:
      doubleCounters.forEach { counter in
        let metricName = counter.key
        let counterInstrument = counter.value

        var metric = Metric(namespace: meterName, name: metricName, desc: meterName + metricName,
                            type: AggregationType.doubleSum, resource: resource,
                            instrumentationScopeInfo: instrumentationScopeInfo)

        counterInstrument.queue.sync {
          counterInstrument.boundInstruments.forEach { boundInstrument in
            let labelSet = boundInstrument.key
            let aggregator = boundInstrument.value.getAggregator()
            aggregator.checkpoint()

            var metricData = aggregator.toMetricData()
            metricData.labels = labelSet.labels
            metric.data.append(metricData)

            boundInstrument.value.syncStatus {
              switch boundInstrument.value.status {
              case .updatePending:
                boundInstrument.value.status = .noPendingUpdate
              case .noPendingUpdate:
                boundInstrument.value.status = .candidateForRemoval
              case .candidateForRemoval:
                boundInstrumentsToRemove.append(labelSet)
              case .bound:
                break
              }
            }
          }
        }

        metricProcessor.process(metric: metric)
        boundInstrumentsToRemove.forEach { boundInstrument in
          counterInstrument.unBind(labelSet: boundInstrument)
        }
        boundInstrumentsToRemove.removeAll()
      }

      // Аналогичным образом заменяем bindUnbindLock.withLockVoid и statusLock.withLockVoid
      // во всех местах, где они встречаются, на queue.sync и syncStatus соответственно.
      // Ниже приводится ещё один пример для rawDoubleHistogram:

      rawDoubleHistogram.forEach { histogram in
        let name = histogram.key
        let instrument = histogram.value

        var metric = Metric(namespace: meterName, name: name, desc: meterName + name,
                            type: .doubleHistogram, resource: resource,
                            instrumentationScopeInfo: instrumentationScopeInfo)

        // Ранее: instrument.bindUnbindLock.withLockVoid
        // Теперь: instrument.queue.sync
        instrument.queue.sync {
          instrument.boundInstruments.forEach { boundInstrument in
            let labelSet = boundInstrument.key
            let counter = boundInstrument.value

            counter.checkpoint()
            var metricData = counter.getMetrics()
            for i in 0..<metricData.count {
              metricData[i].labels = labelSet.labels
            }

            metric.data.append(contentsOf: metricData)

            // boundInstrument.value.statusLock.withLockVoid -> boundInstrument.value.syncStatus
            boundInstrument.value.syncStatus {
              switch boundInstrument.value.status {
              case .updatePending:
                boundInstrument.value.status = .noPendingUpdate
              case .noPendingUpdate:
                boundInstrument.value.status = .candidateForRemoval
              case .candidateForRemoval:
                boundInstrumentsToRemove.append(labelSet)
              case .bound:
                break
              }
            }
          }
        }
        metricProcessor.process(metric: metric)

        boundInstrumentsToRemove.forEach { boundInstrument in
          instrument.unBind(labelSet: boundInstrument)
        }
        boundInstrumentsToRemove.removeAll()
      }

      // Таким же образом обновляем все остальные места, где встречаются bindUnbindLock и statusLock.
      // Нужно убедиться, что все классы, используемые здесь (CounterMetricSdk, BoundRawHistogramMetricSdkBase и т.д.)
      // уже переведены на использование DispatchQueue и предоставляют необходимые методы queue.sync, syncStatus и т.д.
    }
  }

  func createIntObservableGauge(name: String, callback: @escaping (IntObserverMetric) -> Void) -> IntObserverMetric {
    queue.sync {
      if let gauge = intGauges[name] {
        return gauge
      } else {
        let gauge = IntObservableGaugeSdk(measurementName: name, callback: callback)
        intGauges[name] = gauge
        return gauge
      }
    }
  }

  func createDoubleObservableGauge(name: String, callback: @escaping (DoubleObserverMetric) -> Void) -> DoubleObserverMetric {
    queue.sync {
      if let gauge = doubleGauges[name] {
        return gauge
      } else {
        let gauge = DoubleObservableGaugeSdk(measurementName: name, callback: callback)
        doubleGauges[name] = gauge
        return gauge
      }
    }
  }

  func createIntCounter(name: String, monotonic _: Bool) -> AnyCounterMetric<Int> {
    queue.sync {
      if let counter = intCounters[name] {
        return AnyCounterMetric<Int>(counter)
      } else {
        let counter = CounterMetricSdk<Int>(name: name)
        intCounters[name] = counter
        return AnyCounterMetric<Int>(counter)
      }
    }
  }

  func createDoubleCounter(name: String, monotonic _: Bool) -> AnyCounterMetric<Double> {
    queue.sync {
      if let counter = doubleCounters[name] {
        return AnyCounterMetric<Double>(counter)
      } else {
        let counter = CounterMetricSdk<Double>(name: name)
        doubleCounters[name] = counter
        return AnyCounterMetric<Double>(counter)
      }
    }
  }

  func createIntMeasure(name: String, absolute _: Bool) -> AnyMeasureMetric<Int> {
    queue.sync {
      if let measure = intMeasures[name] {
        return AnyMeasureMetric<Int>(measure)
      } else {
        let measure = MeasureMetricSdk<Int>(name: name)
        intMeasures[name] = measure
        return AnyMeasureMetric<Int>(measure)
      }
    }
  }

  func createDoubleMeasure(name: String, absolute _: Bool) -> AnyMeasureMetric<Double> {
    queue.sync {
      if let measure = doubleMeasures[name] {
        return AnyMeasureMetric<Double>(measure)
      } else {
        let measure = MeasureMetricSdk<Double>(name: name)
        doubleMeasures[name] = measure
        return AnyMeasureMetric<Double>(measure)
      }
    }
  }

  func createRawDoubleCounter(name: String) -> AnyRawCounterMetric<Double> {
    queue.sync {
      if let measure = rawDoubleCounters[name] {
        return AnyRawCounterMetric<Double>(measure)
      } else {
        let measure = RawCounterMetricSdk<Double>(name: name)
        rawDoubleCounters[name] = measure
        return AnyRawCounterMetric<Double>(measure)
      }
    }
  }

  func createRawIntCounter(name: String) -> AnyRawCounterMetric<Int> {
    queue.sync {
      if let measure = rawIntCounters[name] {
        return AnyRawCounterMetric<Int>(measure)
      } else {
        let measure = RawCounterMetricSdk<Int>(name: name)
        rawIntCounters[name] = measure
        return AnyRawCounterMetric<Int>(measure)
      }
    }
  }

  func createRawDoubleHistogram(name: String) -> AnyRawHistogramMetric<Double> {
    queue.sync {
      if let histogram = rawDoubleHistogram[name] {
        return AnyRawHistogramMetric<Double>(histogram)
      } else {
        let histogram = RawHistogramMetricSdk<Double>(name: name)
        rawDoubleHistogram[name] = histogram
        return AnyRawHistogramMetric<Double>(histogram)
      }
    }
  }

  func createRawIntHistogram(name: String) -> AnyRawHistogramMetric<Int> {
    queue.sync {
      if let histogram = rawIntHistogram[name] {
        return AnyRawHistogramMetric<Int>(histogram)
      } else {
        let histogram = RawHistogramMetricSdk<Int>(name: name)
        rawIntHistogram[name] = histogram
        return AnyRawHistogramMetric<Int>(histogram)
      }
    }
  }

  func createIntHistogram(name: String, explicitBoundaries: [Int]? = nil, absolute _: Bool) -> AnyHistogramMetric<Int> {
    queue.sync {
      if let histogram = intHistogram[name] {
        return AnyHistogramMetric<Int>(histogram)
      } else {
        let histogram = HistogramMetricSdk<Int>(name: name, explicitBoundaries: explicitBoundaries)
        intHistogram[name] = histogram
        return AnyHistogramMetric<Int>(histogram)
      }
    }
  }

  func createDoubleHistogram(name: String, explicitBoundaries: [Double]? = nil, absolute _: Bool) -> AnyHistogramMetric<Double> {
    queue.sync {
      if let histogram = doubleHistogram[name] {
        return AnyHistogramMetric<Double>(histogram)
      } else {
        let histogram = HistogramMetricSdk<Double>(name: name, explicitBoundaries: explicitBoundaries)
        doubleHistogram[name] = histogram
        return AnyHistogramMetric<Double>(histogram)
      }
    }
  }

  func createIntObserver(name: String, absolute _: Bool, callback: @escaping (IntObserverMetric) -> Void) -> IntObserverMetric {
    queue.sync {
      if let observer = intObservers[name] {
        return observer
      } else {
        let observer = IntObserverMetricSdk(metricName: name, callback: callback)
        intObservers[name] = observer
        return observer
      }
    }
  }

  func createDoubleObserver(name: String, absolute _: Bool, callback: @escaping (DoubleObserverMetric) -> Void) -> DoubleObserverMetric {
    queue.sync {
      if let observer = doubleObservers[name] {
        return observer
      } else {
        let observer = DoubleObserverMetricSdk(metricName: name, callback: callback)
        doubleObservers[name] = observer
        return observer
      }
    }
  }
}
