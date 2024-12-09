//
// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import OpenTelemetrySdk
import OpenTelemetryProtocolExporterCommon
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public class StableOtlpHTTPMetricExporter: StableOtlpHTTPExporterBase, StableMetricExporter {
  var aggregationTemporalitySelector: AggregationTemporalitySelector
  var defaultAggregationSelector: DefaultAggregationSelector

  // Вместо Lock используем serial очередь для потокобезопасного доступа
  private let queue = DispatchQueue(label: "com.example.StableOtlpHTTPMetricExporter.queue")
  private var _pendingMetrics: [StableMetricData] = []
  private var pendingMetrics: [StableMetricData] {
    get { queue.sync { _pendingMetrics } }
    set { queue.sync { _pendingMetrics = newValue } }
  }

  // MARK: - Init

  public init(endpoint: URL,
              config: OtlpConfiguration = OtlpConfiguration(),
              aggregationTemporalitySelector: AggregationTemporalitySelector = AggregationTemporality.alwaysCumulative(),
              defaultAggregationSelector: DefaultAggregationSelector = AggregationSelector.instance,
              useSession: URLSession? = nil,
              envVarHeaders: [(String, String)]? = EnvVarHeaders.attributes) {

    self.aggregationTemporalitySelector = aggregationTemporalitySelector
    self.defaultAggregationSelector = defaultAggregationSelector

    super.init(endpoint: endpoint, config: config, useSession: useSession, envVarHeaders: envVarHeaders)
  }

  // MARK: - StableMetricsExporter

  public func export(metrics: [StableMetricData]) -> ExportResult {
    var sendingMetrics: [StableMetricData] = []

    // Помещаем операции с pendingMetrics в очередь
    queue.sync {
      _pendingMetrics.append(contentsOf: metrics)
      sendingMetrics = _pendingMetrics
      _pendingMetrics.removeAll()
    }

    let body = Opentelemetry_Proto_Collector_Metrics_V1_ExportMetricsServiceRequest.with {
      $0.resourceMetrics = MetricsAdapter.toProtoResourceMetrics(stableMetricData: sendingMetrics)
    }

    var request = createRequest(body: body, endpoint: endpoint)
    request.timeoutInterval = min(TimeInterval.greatestFiniteMagnitude, config.timeout)

    httpClient.send(request: request) { [weak self] result in
      guard let self = self else { return }
      if case .failure(let error) = result {
        // В случае ошибки возвращаем метрики обратно в очередь
        self.queue.sync {
          self._pendingMetrics.append(contentsOf: sendingMetrics)
        }
        print(error)
      }
    }

    return .success
  }

  public func flush() -> ExportResult {
    var exporterResult: ExportResult = .success

    // Копируем метрики для отправки и очищаем локальный список
    let currentPendingMetrics: [StableMetricData] = queue.sync {
      let copy = _pendingMetrics
      return copy
    }

    guard !currentPendingMetrics.isEmpty else {
      return exporterResult
    }

    let body = Opentelemetry_Proto_Collector_Metrics_V1_ExportMetricsServiceRequest.with {
      $0.resourceMetrics = MetricsAdapter.toProtoResourceMetrics(stableMetricData: currentPendingMetrics)
    }

    let semaphore = DispatchSemaphore(value: 0)
    var request = createRequest(body: body, endpoint: endpoint)
    request.timeoutInterval = min(TimeInterval.greatestFiniteMagnitude, config.timeout)

    httpClient.send(request: request) { [weak self] result in
      switch result {
      case .success(_):
        // Если успешно отправили, то удаляем их из pendingMetrics
        self?.queue.sync {
          // Удаляем только те метрики, которые мы пытались отправить
          self?._pendingMetrics.removeAll { currentPendingMetrics.contains($0) }
        }
      case .failure(let error):
        print(error)
        exporterResult = .failure
      }
      semaphore.signal()
    }
    semaphore.wait()

    return exporterResult
  }

  public func shutdown() -> ExportResult {
    return .success
  }

  // MARK: - AggregationTemporalitySelectorProtocol

  public func getAggregationTemporality(for instrument: OpenTelemetrySdk.InstrumentType) -> OpenTelemetrySdk.AggregationTemporality {
    return aggregationTemporalitySelector.getAggregationTemporality(for: instrument)
  }

  // MARK: - DefaultAggregationSelector

  public func getDefaultAggregation(for instrument: OpenTelemetrySdk.InstrumentType) -> OpenTelemetrySdk.Aggregation {
    return defaultAggregationSelector.getDefaultAggregation(for: instrument)
  }
}
