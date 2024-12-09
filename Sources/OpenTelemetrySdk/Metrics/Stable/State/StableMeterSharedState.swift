/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

class StableMeterSharedState {
  // Удаляем Lock и используем одну последовательную очередь для защиты всех общих ресурсов
  private let queue = DispatchQueue(label: "com.example.StableMeterSharedState.queue")

  public private(set) var meterRegistry = [StableMeterSdk]()
  public private(set) var readerStorageRegisteries = [RegisteredReader: MetricStorageRegistry]()
  public private(set) var callbackRegistration = [CallbackRegistration]()

  private let instrumentationScope : InstrumentationScopeInfo

  init(instrumentationScope : InstrumentationScopeInfo, registeredReaders : [RegisteredReader]) {
    self.instrumentationScope = instrumentationScope
    self.readerStorageRegisteries = Dictionary(uniqueKeysWithValues: registeredReaders.map { reader in
      (reader, MetricStorageRegistry())
    })
  }

  func add(meter: StableMeterSdk) {
    queue.sync {
      meterRegistry.append(meter)
    }
  }

  func removeCallback(callback: CallbackRegistration) {
    queue.sync {
      callbackRegistration.removeAll { $0 === callback }
    }
  }

  func registerCallback(callback: CallbackRegistration) {
    queue.sync {
      callbackRegistration.append(callback)
    }
  }

  func registerSynchronousMetricStorage(instrument: InstrumentDescriptor,
                                        meterProviderSharedState: MeterProviderSharedState) -> WritableMetricStorage {
    return queue.sync {
      var registeredStorages = [SynchronousMetricStorage]()
      for (reader, registry) in readerStorageRegisteries {
        for registeredView in reader.registry.findViews(descriptor: instrument, meterScope: instrumentationScope) {
          if type(of: registeredView.view.aggregation) == DropAggregation.self {
            continue
          }
          if let storage = SynchronousMetricStorage.create(
            registeredReader: reader,
            registeredView: registeredView,
            descriptor: instrument,
            exemplarFilter: meterProviderSharedState.exemplarFilter
          ) as? SynchronousMetricStorage {
            registeredStorages.append(registry.register(newStorage: storage) as! SynchronousMetricStorage)
          }
        }
      }
      if registeredStorages.count == 1 {
        return registeredStorages[0]
      }
      return MultiWritableMetricStorage(storages: registeredStorages)
    }
  }

  func registerObservableMeasurement(instrumentDescriptor: InstrumentDescriptor) -> StableObservableMeasurementSdk {
    return queue.sync {
      var registeredStorages = [AsynchronousMetricStorage]()
      for (reader, registry) in readerStorageRegisteries {
        for registeredView in reader.registry.findViews(descriptor: instrumentDescriptor, meterScope: instrumentationScope) {
          if type(of: registeredView.view.aggregation) == DropAggregation.self {
            continue
          }
          if let storage = AsynchronousMetricStorage.create(
            registeredReader: reader,
            registeredView: registeredView,
            instrumentDescriptor: instrumentDescriptor
          ) as? AsynchronousMetricStorage {
            registeredStorages.append(registry.register(newStorage: storage) as! AsynchronousMetricStorage)
          }
        }
      }

      return StableObservableMeasurementSdk(insturmentScope: instrumentationScope,
                                            descriptor: instrumentDescriptor,
                                            storages: registeredStorages)
    }
  }

  func collectAll(registeredReader: RegisteredReader,
                  meterProviderSharedState: MeterProviderSharedState,
                  epochNanos: UInt64) -> [StableMetricData] {

    // Шаг 1: копируем callbacks внутри очереди
    let currentRegisteredCallbacks = queue.sync {
      return self.callbackRegistration
    }

    // Шаг 2: выполняем callbacks вне очереди, чтобы избежать потенциальных дедлоков
    currentRegisteredCallbacks.forEach {
      $0.execute(reader: registeredReader,
                 startEpochNanos: meterProviderSharedState.startEpochNanos,
                 epochNanos: epochNanos)
    }

    // Шаг 3: Снова заходим в очередь для безопасного доступа к registry и сбору метрик
    return queue.sync {
      var result = [StableMetricData]()
      if let storages = readerStorageRegisteries[registeredReader]?.getStorages() {
        for var storage in storages {
          let metricData = storage.collect(resource: meterProviderSharedState.resource,
                                           scope: instrumentationScope,
                                           startEpochNanos: meterProviderSharedState.startEpochNanos,
                                           epochNanos: epochNanos)
          if !metricData.isEmpty() {
            result.append(metricData)
          }
        }
      }
      return result
    }
  }
}
