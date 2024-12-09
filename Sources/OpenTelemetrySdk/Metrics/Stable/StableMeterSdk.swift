/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import OpenTelemetryApi

class StableMeterSdk: StableMeter {
  // Эти состояния, судя по всему, могут изменяться и читаться из разных потоков,
  // поэтому их доступ должен быть синхронизирован.
  private var _meterProviderSharedState: MeterProviderSharedState
  private var _meterSharedState: StableMeterSharedState
  public private(set) var instrumentationScopeInfo: InstrumentationScopeInfo

  // Очередь для потокобезопасного доступа к состоянию
  private let queue = DispatchQueue(label: "com.example.StableMeterSdk.queue")

  init(meterProviderSharedState: inout MeterProviderSharedState,
       instrumentScope: InstrumentationScopeInfo,
       registeredReaders: inout [RegisteredReader]) {

    // Инициализируем внутреннее состояние один раз при создании
    // Так как это init, мы можем взять значения из inout и сохранить их во внутренние переменные
    _meterProviderSharedState = meterProviderSharedState
    _meterSharedState = StableMeterSharedState(instrumentationScope: instrumentScope,
                                               registeredReaders: registeredReaders)
    self.instrumentationScopeInfo = instrumentScope
  }

  func counterBuilder(name: String) -> OpenTelemetryApi.LongCounterBuilder {
    // Выполняем доступ к состоянию внутри queue.sync
    return queue.sync {
      return LongCounterMeterBuilderSdk(meterProviderSharedState: &_meterProviderSharedState,
                                        meterSharedState: &_meterSharedState,
                                        name: name)
    }
  }

  func upDownCounterBuilder(name: String) -> OpenTelemetryApi.LongUpDownCounterBuilder {
    return queue.sync {
      return LongUpDownCounterBuilderSdk(meterProviderSharedState: &_meterProviderSharedState,
                                         meterSharedState: &_meterSharedState,
                                         name: name)
    }
  }

  func histogramBuilder(name: String) -> OpenTelemetryApi.DoubleHistogramBuilder {
    return queue.sync {
      return DoubleHistogramMeterBuilderSdk(meterProviderSharedState: &_meterProviderSharedState,
                                            meterSharedState: &_meterSharedState,
                                            name: name)
    }
  }

  func gaugeBuilder(name: String) -> OpenTelemetryApi.DoubleGaugeBuilder {
    return queue.sync {
      return DoubleGaugeBuilderSdk(meterProviderSharedState: &_meterProviderSharedState,
                                   meterSharedState: &_meterSharedState,
                                   name: name)
    }
  }

  func collectAll(registerReader: RegisteredReader, epochNanos: UInt64) -> [StableMetricData] {
    // Доступ к состоянию под защитой очереди
    return queue.sync {
      return _meterSharedState.collectAll(registeredReader: registerReader,
                                          meterProviderSharedState: _meterProviderSharedState,
                                          epochNanos: epochNanos)
    }
  }
}
