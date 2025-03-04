/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

#if SPM_BUILD
import _Datadog_Private
#endif

internal class DDSpan: OTSpan {
    /// The `Tracer` which created this span.
    private let ddTracer: Tracer
    /// Span context.
    internal let ddContext: DDSpanContext
    /// Span creation date
    internal let startTime: Date
    /// Builds the `Span` from user input.
    internal let spanBuilder: SpanEventBuilder
    /// Writes the `Span` to file.
    private let spanOutput: SpanOutput
    /// Writes span logs to output. `nil` if Logging feature is disabled.
    private let logOutput: LoggingForTracingAdapter.AdaptedLogOutput?

    /// Queue used for synchronizing mutable properties access.
    private let queue: DispatchQueue
    /// Unsynchronized span operation name. Must be accessed on `queue`.
    private var unsafeOperationName: String
    /// Unsynchronized span tags.  Must be accessed on `queue`.
    private var unsafeTags: [String: Encodable]
    /// Unsychronized span log fields.  Must be accessed on `queue`.
    private var unsafeLogFields: [[String: Encodable]]
    /// Unsychronized span completion.  Must be accessed on `queue`.
    private var unsafeIsFinished: Bool

    private var activityReference: ActivityReference?

    init(
        tracer: Tracer,
        context: DDSpanContext,
        operationName: String,
        startTime: Date,
        tags: [String: Encodable]
    ) {
        self.ddTracer = tracer
        self.ddContext = context
        self.startTime = startTime
        self.spanBuilder = tracer.spanBuilder
        self.spanOutput = tracer.spanOutput
        self.logOutput = tracer.logOutput
        self.queue = ddTracer.queue // share the queue among all spans
        self.unsafeOperationName = operationName
        self.unsafeTags = tags
        self.unsafeLogFields = []
        self.unsafeIsFinished = false
    }

    // MARK: - Open Tracing interface

    var context: OTSpanContext {
        return ddContext
    }

    func tracer() -> OTTracer {
        return ddTracer
    }

    func setOperationName(_ operationName: String) {
        queue.async {
            if self.warnIfFinished("setOperationName(_:)") {
                return
            }
            self.unsafeOperationName = operationName
        }
    }

    func setTag(key: String, value: Encodable) {
        queue.async {
            if self.warnIfFinished("setTag(key:value:)") {
                return
            }
            self.unsafeTags[key] = value
        }
    }

    func setBaggageItem(key: String, value: String) {
        let isFinished = queue.sync { self.warnIfFinished("setBaggageItem(key:value:)") }
        if !isFinished {
            // Baggage items must be accessed outside the `tracer.queue` as it uses that queue for internal sync.
            ddContext.baggageItems.set(key: key, value: value)
        }
    }

    func baggageItem(withKey key: String) -> String? {
        let isFinished = queue.sync { self.warnIfFinished("baggageItem(withKey:)") }
        // Baggage items must be accessed outside the `tracer.queue` as it uses that queue for internal sync.
        return !isFinished ? ddContext.baggageItems.get(key: key) : nil
    }

    @discardableResult
    func setActive() -> OTSpan {
        activityReference = ActivityReference()
        if let activityReference = activityReference {
            ddTracer.activeSpansPool.addSpan(span: self, activityReference: activityReference)
        }
        return self
    }

    func log(fields: [String: Encodable], timestamp: Date) {
        queue.async {
            if self.warnIfFinished("log(fields:timestamp:)") {
                return
            }
            self.unsafeLogFields.append(fields)
        }
        sendSpanLogs(fields: fields, date: timestamp)
    }

    func finish(at time: Date) {
        let isFinished: Bool = queue.sync {
            let wasFinished = self.warnIfFinished("finish(at:)")
            self.unsafeIsFinished = true
            return wasFinished
        }

        if !isFinished {
            if let activity = activityReference {
                ddTracer.activeSpansPool.removeSpan(activityReference: activity)
            }
            sendSpan(finishTime: time)
        }
    }

    // MARK: - Writing SpanEvent

    /// Sends span event for given `DDSpan`.
    private func sendSpan(finishTime: Date) {
        // Baggage items must be accessed outside the `tracer.queue` as it uses that queue for internal sync.
        let baggageItems = ddContext.baggageItems.all

        // This queue adds performance optimisation by reading all `unsafe*` values in one block and performing
        // the `builder.createSpan()` off the main thread. This is important as the span creation includes
        // attributes encoding to JSON string values (for tags and extra user info). It captures `self` strongly
        // as it is very likely to be deallocated after return.
        queue.async {
            let span = self.spanBuilder.createSpanEvent(
                traceID: self.ddContext.traceID,
                spanID: self.ddContext.spanID,
                parentSpanID: self.ddContext.parentSpanID,
                operationName: self.unsafeOperationName,
                startTime: self.startTime,
                finishTime: finishTime,
                tags: self.unsafeTags,
                baggageItems: baggageItems,
                logFields: self.unsafeLogFields
            )
            self.spanOutput.write(span: span)
        }
    }

    private func sendSpanLogs(fields: [String: Encodable], date: Date) {
        guard let logOutput = logOutput else {
            queue.async {
                userLogger.warn("The log for span \"\(self.unsafeOperationName)\" will not be send, because the Logging feature is disabled.")
            }
            return
        }
        logOutput.writeLog(withSpanContext: ddContext, fields: fields, date: date)
    }

    // MARK: - Private

    private func warnIfFinished(_ methodName: String) -> Bool {
        return warn(
            if: unsafeIsFinished,
            message: "🔥 Calling `\(methodName)` on a finished span (\"\(unsafeOperationName)\") is not allowed."
        )
    }
}
