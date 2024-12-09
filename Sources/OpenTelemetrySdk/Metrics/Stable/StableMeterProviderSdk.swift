/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import OpenTelemetryApi

public class MeterProviderError: Error {}

public class StableMeterProviderSdk: StableMeterProvider {
  private static let defaultMeterName = "unknown"

  // Вместо Lock используем serial очередь для всех операций с общим состоянием
  private let queue = DispatchQueue(label: "com.example.StableMeterProviderSdk.queue")

  var meterProviderSharedState: MeterProviderSharedState

  // Доступ к registeredReaders и registeredViews только через queue.sync
  private var _registeredReaders = [RegisteredReader]()
  private var registeredReaders: [RegisteredReader] {
    get { queue.sync { _registeredReaders } }
    set { queue.sync { _registeredReaders = newValue } }
  }

  private var _registeredViews = [RegisteredView]()
  private var registeredViews: [RegisteredView] {
    get { queue.sync { _registeredViews } }
    set { queue.sync { _registeredViews = newValue } }
  }

  var componentRegistry: ComponentRegistry<StableMeterSdk>!

  public func get(name: String) -> StableMeter {
    meterBuilder(name: name).build()
  }

  public func meterBuilder(name: String) -> MeterBuilder {
    // Проверяем registeredReaders только внутри queue
    let hasNoReaders = queue.sync { _registeredReaders.isEmpty }
    if hasNoReaders {
      return DefaultStableMeterProvider.noop()
    }

    var safeName = name
    if safeName.isEmpty {
      safeName = Self.defaultMeterName
    }

    // Здесь можно безопасно использовать componentRegistry,
    // предполагая, что он инициализируется один раз в init и далее не мутирует.
    return MeterBuilderSdk(registry: componentRegistry, instrumentationScopeName: safeName)
  }

  public static func builder() -> StableMeterProviderBuilder {
    return StableMeterProviderBuilder()
  }

  init(registeredViews: [RegisteredView],
       metricReaders: [StableMetricReader],
       clock: Clock,
       resource: Resource,
       exemplarFilter: ExemplarFilter)
  {
    let startEpochNano = Date().timeIntervalSince1970.toNanoseconds

    // Инициализация массива в init безопасна без очереди
    self._registeredViews = registeredViews
    self._registeredReaders = metricReaders.map { reader in
      RegisteredReader(reader: reader, registry: StableViewRegistry(aggregationSelector: reader, registeredViews: registeredViews))
    }

    meterProviderSharedState = MeterProviderSharedState(clock: clock, resource: resource, startEpochNanos: startEpochNano, exemplarFilter: exemplarFilter)

    componentRegistry = ComponentRegistry { scope in
      // Используем in-out ссылки, но они будут использоваться в очереди
      StableMeterSdk(meterProviderSharedState: &self.meterProviderSharedState, instrumentScope: scope, registeredReaders: &self._registeredReaders)
    }

    // Регистрация продюсеров для каждого reader.
    // Пока мы в init, нет параллельных обращений, это безопасно.
    for i in 0..<_registeredReaders.count {
      let producer = LeasedMetricProducer(registry: componentRegistry,
                                          sharedState: meterProviderSharedState,
                                          registeredReader: _registeredReaders[i],
                                          queue: queue)
      _registeredReaders[i].reader.register(registration: producer)
      _registeredReaders[i].lastCollectedEpochNanos = startEpochNano
    }
  }

  public func shutdown() -> ExportResult {
    // Все операции с registeredReaders через очередь
    return queue.sync {
      do {
        for reader in _registeredReaders {
          guard reader.reader.shutdown() == .success else {
            throw MeterProviderError()
          }
        }
      } catch {
        return .failure
      }
      return .success
    }
  }

  public func forceFlush() -> ExportResult {
    return queue.sync {
      do {
        for reader in _registeredReaders {
          guard reader.reader.forceFlush() == .success else {
            throw MeterProviderError()
          }
        }
      } catch {
        return .failure
      }
      return .success
    }
  }

  private class LeasedMetricProducer: MetricProducer {
    private let registry: ComponentRegistry<StableMeterSdk>
    private var sharedState: MeterProviderSharedState
    private var registeredReader: RegisteredReader

    // Передадим очередь из MeterProvider, чтобы синхронизировать доступ к общему состоянию.
    private let queue: DispatchQueue

    init(registry: ComponentRegistry<StableMeterSdk>,
         sharedState: MeterProviderSharedState,
         registeredReader: RegisteredReader,
         queue: DispatchQueue) {
      self.registry = registry
      self.sharedState = sharedState
      self.registeredReader = registeredReader
      self.queue = queue
    }

    func collectAllMetrics() -> [StableMetricData] {
      // Доступ к registry.getComponents() и изменению registeredReader в очереди
      return queue.sync {
        let meters = registry.getComponents()
        var result = [StableMetricData]()
        let collectTime = sharedState.clock.nanoTime
        for meter in meters {
          result.append(contentsOf: meter.collectAll(registerReader: registeredReader, epochNanos: collectTime))
        }
        registeredReader.lastCollectedEpochNanos = collectTime
        return result
      }
    }
  }
}
