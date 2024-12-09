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

public func defaultOltpHttpLoggingEndpoint() -> URL {
  URL(string: "http://localhost:4318/v1/logs")!
}

public class OtlpHttpLogExporter: OtlpHttpExporterBase, LogRecordExporter {
  private var pendingLogRecords: [ReadableLogRecord] = []
  private let queue = DispatchQueue(label: "OtlpHttpLogExporter.queue")

  override public init(endpoint: URL = defaultOltpHttpLoggingEndpoint(),
                       config: OtlpConfiguration = OtlpConfiguration(),
                       useSession: URLSession? = nil,
                       envVarHeaders: [(String, String)]? = EnvVarHeaders.attributes) {
    super.init(endpoint: endpoint, config: config, useSession: useSession, envVarHeaders: envVarHeaders)
  }

  public func export(logRecords: [OpenTelemetrySdk.ReadableLogRecord],
                     explicitTimeout: TimeInterval? = nil) -> OpenTelemetrySdk.ExportResult {
    var sendingLogRecords: [ReadableLogRecord] = []

    // Атомарно перемещаем все входящие записи в sendingLogRecords и очищаем pendingLogRecords
    queue.sync {
      pendingLogRecords.append(contentsOf: logRecords)
      sendingLogRecords = pendingLogRecords
      pendingLogRecords.removeAll()
    }

    let body = Opentelemetry_Proto_Collector_Logs_V1_ExportLogsServiceRequest.with { request in
      request.resourceLogs = LogRecordAdapter.toProtoResourceRecordLog(logRecordList: sendingLogRecords)
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

    request.timeoutInterval = min(explicitTimeout ?? TimeInterval.greatestFiniteMagnitude, config.timeout)
    httpClient.send(request: request) { [weak self] result in
      switch result {
      case .success:
        // Успех – ничего не делаем, так как метрики уже удалены из pendingLogRecords
        break
      case let .failure(error):
        // В случае ошибки возвращаем отправленные записи обратно в pendingLogRecords
        self?.queue.sync {
          self?.pendingLogRecords.append(contentsOf: sendingLogRecords)
        }
        print(error)
      }
    }

    return .success
  }

  public func forceFlush(explicitTimeout: TimeInterval? = nil) -> ExportResult {
    flush(explicitTimeout: explicitTimeout)
  }

  public func flush(explicitTimeout: TimeInterval? = nil) -> ExportResult {
    var exporterResult: ExportResult = .success

    // Копируем текущее состояние pendingLogRecords для отправки
    let recordsToSend: [ReadableLogRecord] = queue.sync {
      return self.pendingLogRecords
    }

    guard !recordsToSend.isEmpty else {
      return exporterResult
    }

    let body = Opentelemetry_Proto_Collector_Logs_V1_ExportLogsServiceRequest.with { request in
      request.resourceLogs = LogRecordAdapter.toProtoResourceRecordLog(logRecordList: recordsToSend)
    }

    let semaphore = DispatchSemaphore(value: 0)
    var request = createRequest(body: body, endpoint: endpoint)
    request.timeoutInterval = min(explicitTimeout ?? TimeInterval.greatestFiniteMagnitude, config.timeout)

    if let headers = envVarHeaders {
      headers.forEach { key, value in
        request.addValue(value, forHTTPHeaderField: key)
      }
    } else if let headers = config.headers {
      headers.forEach { key, value in
        request.addValue(value, forHTTPHeaderField: key)
      }
    }

    httpClient.send(request: request) { result in
      switch result {
      case .success:
        exporterResult = .success
      case let .failure(error):
        print(error)
        exporterResult = .failure
      }
      semaphore.signal()
    }
    semaphore.wait()

    return exporterResult
  }
}
