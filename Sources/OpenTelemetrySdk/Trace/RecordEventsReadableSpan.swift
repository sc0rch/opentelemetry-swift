/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import OpenTelemetryApi

/// Implementation for the Span class that records trace events.
public class RecordEventsReadableSpan: ReadableSpan {
  // MARK: - Internal State Queues
  // Очередь для статуса, имени, флага окончания, флага записи, endTime.
  // concurrent + barrier для записи.
  fileprivate let internalStatusQueue = DispatchQueue(label: "org.opentelemetry.RecordEventsReadableSpan.internalStatusQueue", attributes: .concurrent)
  // Очередь для атрибутов.
  private let attributesQueue = DispatchQueue(label: "org.opentelemetry.RecordEventsReadableSpan.attributesQueue")
  // Очередь для событий.
  private let eventsQueue = DispatchQueue(label: "org.opentelemetry.RecordEventsReadableSpan.eventsQueue")

  // MARK: - Internal Properties Protected by internalStatusQueue
  fileprivate var internalName: String
  fileprivate var internalStatus: Status = .unset
  fileprivate var internalEnd = false
  fileprivate var internalIsRecording = true
  fileprivate var internalEndTime: Date?

  public var name: String {
    get {
      internalStatusQueue.sync {
        internalName
      }
    }
    set {
      internalStatusQueue.sync(flags: .barrier) {
        if !internalEnd {
          internalName = newValue
        }
      }
    }
  }

  public var status: Status {
    get {
      internalStatusQueue.sync {
        internalStatus
      }
    }
    set {
      internalStatusQueue.sync(flags: .barrier) {
        if !internalEnd {
          internalStatus = newValue
        }
      }
    }
  }

  public var hasEnded: Bool {
    internalStatusQueue.sync {
      internalEnd
    }
  }

  public var isRecording: Bool {
    internalStatusQueue.sync {
      internalIsRecording
    }
  }

  public var endTime: Date? {
    internalStatusQueue.sync {
      internalEndTime
    }
  }

  // MARK: - Other Public Properties
  public private(set) var spanLimits: SpanLimits
  public private(set) var context: SpanContext
  public private(set) var parentContext: SpanContext?
  public private(set) var hasRemoteParent: Bool
  public private(set) var spanProcessor: SpanProcessor
  public private(set) var links = [SpanData.Link]()
  public private(set) var totalRecordedLinks: Int
  public private(set) var maxNumberOfAttributes: Int
  public private(set) var maxNumberOfAttributesPerEvent: Int
  public private(set) var kind: SpanKind
  public private(set) var clock: Clock
  public private(set) var resource: Resource
  public private(set) var instrumentationScopeInfo: InstrumentationScopeInfo
  public private(set) var startTime: Date

  // MARK: - Attributes Protected by attributesQueue
  private var attributes: AttributesDictionary
  private var totalAttributeCount: Int

  // MARK: - Events Protected by eventsQueue
  public private(set) var events: ArrayWithCapacity<SpanData.Event>
  private var totalRecordedEvents = 0

  public var latency: TimeInterval {
    return endTime?.timeIntervalSince(startTime) ?? clock.now.timeIntervalSince(startTime)
  }

  private init(context: SpanContext,
               name: String,
               instrumentationScopeInfo: InstrumentationScopeInfo,
               kind: SpanKind,
               parentContext: SpanContext?,
               hasRemoteParent: Bool,
               spanLimits: SpanLimits,
               spanProcessor: SpanProcessor,
               clock: Clock,
               resource: Resource,
               attributes: AttributesDictionary,
               links: [SpanData.Link],
               totalRecordedLinks: Int,
               startTime: Date?)
  {
    self.context = context
    self.internalName = name
    self.instrumentationScopeInfo = instrumentationScopeInfo
    self.parentContext = parentContext
    self.hasRemoteParent = hasRemoteParent
    self.spanLimits = spanLimits
    self.links = links
    self.totalRecordedLinks = totalRecordedLinks
    self.kind = kind
    self.spanProcessor = spanProcessor
    self.clock = clock
    self.resource = resource
    self.startTime = startTime ?? clock.now
    self.attributes = attributes
    self.totalAttributeCount = attributes.count
    events = ArrayWithCapacity<SpanData.Event>(capacity: spanLimits.eventCountLimit)
    maxNumberOfAttributes = spanLimits.attributeCountLimit
    maxNumberOfAttributesPerEvent = spanLimits.attributePerEventCountLimit
  }

  public static func startSpan(context: SpanContext,
                               name: String,
                               instrumentationScopeInfo: InstrumentationScopeInfo,
                               kind: SpanKind,
                               parentContext: SpanContext?,
                               hasRemoteParent: Bool,
                               spanLimits: SpanLimits,
                               spanProcessor: SpanProcessor,
                               clock: Clock,
                               resource: Resource,
                               attributes: AttributesDictionary,
                               links: [SpanData.Link],
                               totalRecordedLinks: Int,
                               startTime: Date?) -> RecordEventsReadableSpan
  {
    let span = RecordEventsReadableSpan(context: context,
                                        name: name,
                                        instrumentationScopeInfo: instrumentationScopeInfo,
                                        kind: kind,
                                        parentContext: parentContext,
                                        hasRemoteParent: hasRemoteParent,
                                        spanLimits: spanLimits,
                                        spanProcessor: spanProcessor,
                                        clock: clock,
                                        resource: resource,
                                        attributes: attributes,
                                        links: links,
                                        totalRecordedLinks: totalRecordedLinks,
                                        startTime: startTime)
    spanProcessor.onStart(parentContext: parentContext, span: span)
    return span
  }

  public func toSpanData() -> SpanData {
    let currentName = name
    let currentStatus = status
    let currentHasEnded = hasEnded
    let currentEndTime = endTime ?? clock.now
    let currentAttributes = attributesQueue.sync { attributes.attributes }
    let currentTotalAttributeCount = attributesQueue.sync { totalAttributeCount }
    let currentEvents = eventsQueue.sync { events.array }
    let currentTotalRecordedEvents = getTotalRecordedEvents()

    return SpanData(traceId: context.traceId,
                    spanId: context.spanId,
                    traceFlags: context.traceFlags,
                    traceState: context.traceState,
                    parentSpanId: parentContext?.spanId,
                    resource: resource,
                    instrumentationScope: instrumentationScopeInfo,
                    name: currentName,
                    kind: kind,
                    startTime: startTime,
                    attributes: currentAttributes,
                    events: currentEvents,
                    links: links,
                    status: currentStatus,
                    endTime: currentEndTime,
                    hasRemoteParent: hasRemoteParent,
                    hasEnded: currentHasEnded,
                    totalRecordedEvents: currentTotalRecordedEvents,
                    totalRecordedLinks: totalRecordedLinks,
                    totalAttributeCount: currentTotalAttributeCount)
  }

  public func setAttribute(key: String, value: AttributeValue?) {
    // Проверяем состояние записи под internalStatusQueue
    guard internalStatusQueue.sync(execute: { internalIsRecording && !internalEnd }) else { return }

    attributesQueue.sync {
      if value == nil {
        // Удаление атрибута
        if attributes.removeValueForKey(key: key) != nil {
          totalAttributeCount -= 1
        }
        return
      }

      // Добавление или замена атрибута
      totalAttributeCount += 1
      // Проверяем лимит атрибутов
      if attributes[key] == nil, totalAttributeCount > maxNumberOfAttributes {
        // Превышен лимит — игнорируем этот атрибут
        totalAttributeCount -= 1
        return
      }
      attributes[key] = value
    }
  }

  public func addEvent(name: String) {
    addEvent(event: SpanData.Event(name: name, timestamp: clock.now))
  }

  public func addEvent(name: String, timestamp: Date) {
    addEvent(event: SpanData.Event(name: name, timestamp: timestamp))
  }

  public func addEvent(name: String, attributes: [String: AttributeValue]) {
    var limitedAttributes = AttributesDictionary(capacity: maxNumberOfAttributesPerEvent)
    limitedAttributes.updateValues(attributes: attributes)
    addEvent(event: SpanData.Event(name: name, timestamp: clock.now, attributes: limitedAttributes.attributes))
  }

  public func addEvent(name: String, attributes: [String: AttributeValue], timestamp: Date) {
    var limitedAttributes = AttributesDictionary(capacity: maxNumberOfAttributesPerEvent)
    limitedAttributes.updateValues(attributes: attributes)
    addEvent(event: SpanData.Event(name: name, timestamp: timestamp, attributes: limitedAttributes.attributes))
  }

  private func addEvent(event: SpanData.Event) {
    // Проверяем состояние записи
    guard internalStatusQueue.sync(execute: { internalIsRecording && !internalEnd }) else { return }

    eventsQueue.sync {
      events.append(event)
      totalRecordedEvents += 1
    }
  }

  public func end() {
    end(time: clock.now)
  }

  public func end(time: Date) {
    let alreadyEnded = internalStatusQueue.sync(flags: .barrier) { () -> Bool in
      if internalEnd {
        return true
      }
      internalEnd = true
      internalIsRecording = false
      internalEndTime = time
      return false
    }

    if alreadyEnded {
      return
    }

    // Контекст и spanProcessor
    OpenTelemetry.instance.contextProvider.removeContextForSpan(self)
    spanProcessor.onEnd(span: self)
  }

  public var description: String {
    return "RecordEventsReadableSpan{}"
  }

  internal func getTotalRecordedEvents() -> Int {
    eventsQueue.sync {
      totalRecordedEvents
    }
  }

  internal func getDroppedLinksCount() -> Int {
    return totalRecordedLinks - links.count
  }

  public func recordException(_ exception: SpanException) {
    recordException(exception, timestamp: clock.now)
  }

  public func recordException(_ exception: any SpanException, timestamp: Date) {
    recordException(exception, attributes: [:], timestamp: timestamp)
  }

  public func recordException(_ exception: any SpanException, attributes: [String : AttributeValue]) {
    recordException(exception, attributes: attributes, timestamp: clock.now)
  }

  public func recordException(_ exception: any SpanException, attributes: [String : AttributeValue], timestamp: Date) {
    var limitedAttributes = AttributesDictionary(capacity: maxNumberOfAttributesPerEvent)
    limitedAttributes.updateValues(attributes: attributes)
    limitedAttributes.updateValues(attributes: exception.eventAttributes)
    addEvent(event: SpanData.Event(name: SemanticAttributes.exception.rawValue,
                                   timestamp: timestamp,
                                   attributes: limitedAttributes.attributes))
  }
}

extension SpanException {
  fileprivate var eventAttributes: [String: AttributeValue] {
    [
      SemanticAttributes.exceptionType.rawValue: type,
      SemanticAttributes.exceptionMessage.rawValue: message,
      SemanticAttributes.exceptionStacktrace.rawValue: stackTrace?.joined(separator: "\n")
    ].compactMapValues { value in
      if let value, !value.isEmpty {
        return .string(value)
      }
      return nil
    }
  }
}
