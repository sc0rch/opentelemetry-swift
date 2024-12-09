//
// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0
//

import OpenTelemetrySdk
import OpenTelemetryProtocolExporterCommon
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public func defaultOltpHTTPMetricsEndpoint() -> URL {
  URL(string: "http://localhost:4318/v1/metrics")!
}

public class OtlpHttpMetricExporter: OtlpHttpExporterBase, MetricExporter {
  private var _pendingMetrics: [Metric] = []
  private let queue = DispatchQueue(label: "OtlpHttpMetricExporter.queue")

  override
  public init(endpoint: URL = defaultOltpHTTPMetricsEndpoint(),
              config: OtlpConfiguration = OtlpConfiguration(),
              useSession: URLSession? = nil,
              envVarHeaders: [(String,String)]? = EnvVarHeaders.attributes) {
    super.init(endpoint: endpoint, config: config, useSession: useSession, envVarHeaders: envVarHeaders)
  }

  public func export(metrics: [Metric], shouldCancel: (() -> Bool)?) -> MetricExporterResultCode {
    // Получаем метрики для отправки и очищаем локальный список
    let sendingMetrics: [Metric] = queue.sync {
      _pendingMetrics.append(contentsOf: metrics)
      let toSend = _pendingMetrics
      _pendingMetrics.removeAll()
      return toSend
    }

    let body = Opentelemetry_Proto_Collector_Metrics_V1_ExportMetricsServiceRequest.with {
      $0.resourceMetrics = MetricsAdapter.toProtoResourceMetrics(metricDataList: sendingMetrics)
    }

    var request = createRequest(body: body, endpoint: endpoint)
    if let headers = envVarHeaders {
      headers.forEach { key, value in
        request.addValue(value, forHTTPHeaderField: key)
      }
    } else if let headers = config.headers {
      headers.forEach { key, value in
        request.addValue(value, forHTTPHeaderField: key)
      }
    }

    httpClient.send(request: request) { [weak self] result in
      guard let self = self else { return }
      if case .failure(let error) = result {
        // Если отправка не удалась, возвращаем метрики обратно в pendingMetrics
        self.queue.sync {
          self._pendingMetrics.append(contentsOf: sendingMetrics)
        }
        print(error)
      }
    }

    return .success
  }

  public func flush() -> MetricExporterResultCode {
    var exporterResult: MetricExporterResultCode = .success

    let currentPendingMetrics: [Metric] = queue.sync {
      return _pendingMetrics
    }

    guard !currentPendingMetrics.isEmpty else {
      return exporterResult
    }

    let body = Opentelemetry_Proto_Collector_Metrics_V1_ExportMetricsServiceRequest.with {
      $0.resourceMetrics = MetricsAdapter.toProtoResourceMetrics(metricDataList: currentPendingMetrics)
    }

    let semaphore = DispatchSemaphore(value: 0)
    let request = createRequest(body: body, endpoint: endpoint)
    httpClient.send(request: request) { result in
      switch result {
      case .success(_):
        break
      case .failure(let error):
        print(error)
        exporterResult = .failureNotRetryable
      }
      semaphore.signal()
    }
    semaphore.wait()

    return exporterResult
  }
}
