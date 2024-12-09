//
// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import OpenTelemetryProtocolExporterCommon
import OpenTelemetrySdk
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public func defaultOltpHttpTracesEndpoint() -> URL {
  URL(string: "http://localhost:4318/v1/traces")!
}

public class OtlpHttpTraceExporter: OtlpHttpExporterBase, SpanExporter {
  // Вместо Lock используем serial очередь для потокобезопасности
  private let queue = DispatchQueue(label: "OtlpHttpTraceExporter.queue")
  private var _pendingSpans: [SpanData] = []
  private var pendingSpans: [SpanData] {
    get { queue.sync { _pendingSpans } }
    set { queue.sync { _pendingSpans = newValue } }
  }

  override
  public init(endpoint: URL = defaultOltpHttpTracesEndpoint(),
              config: OtlpConfiguration = OtlpConfiguration(),
              useSession: URLSession? = nil,
              envVarHeaders: [(String, String)]? = EnvVarHeaders.attributes) {
    super.init(endpoint: endpoint, config: config, useSession: useSession)
  }

  public func export(spans: [SpanData], explicitTimeout: TimeInterval? = nil) -> SpanExporterResultCode {
    var sendingSpans: [SpanData] = []

    // Добавляем новые спаны и подготавливаем к отправке
    queue.sync {
      _pendingSpans.append(contentsOf: spans)
      sendingSpans = _pendingSpans
      _pendingSpans.removeAll()
    }

    let body = Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest.with {
      $0.resourceSpans = SpanAdapter.toProtoResourceSpans(spanDataList: sendingSpans)
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
      if case let .failure(error) = result {
        // В случае ошибки возвращаем спаны обратно
        self.queue.sync {
          self._pendingSpans.append(contentsOf: sendingSpans)
        }
        print(error)
      }
    }

    return .success
  }

  public func flush(explicitTimeout: TimeInterval? = nil) -> SpanExporterResultCode {
    var resultValue: SpanExporterResultCode = .success
    var currentPendingSpans: [SpanData] = []

    // Берём текущее состояние pendingSpans
    queue.sync {
      currentPendingSpans = _pendingSpans
    }

    if !currentPendingSpans.isEmpty {
      let body = Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest.with {
        $0.resourceSpans = SpanAdapter.toProtoResourceSpans(spanDataList: currentPendingSpans)
      }
      let semaphore = DispatchSemaphore(value: 0)
      let request = createRequest(body: body, endpoint: endpoint)

      httpClient.send(request: request) { result in
        switch result {
        case .success:
          break
        case let .failure(error):
          print(error)
          resultValue = .failure
        }
        semaphore.signal()
      }
      semaphore.wait()
    }

    return resultValue
  }
}
