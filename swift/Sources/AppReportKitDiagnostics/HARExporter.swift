import AppReportKit
import Foundation

public struct HARExporter {
    private let creatorVersion: String

    public init(creatorVersion: String = AppReportKitVersion.current) {
        self.creatorVersion = creatorVersion
    }

    public func export(_ events: [NetworkEvent]) throws -> Data {
        let document = HARDocument(
            log: .init(
                version: "1.2",
                creator: .init(name: "AppReportKitDiagnostics", version: creatorVersion),
                entries: events.map(makeEntry(for:))
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    private func makeEntry(for event: NetworkEvent) -> HAREntry {
        let request = HARRequest(
            method: event.method,
            url: event.redactedURLString,
            httpVersion: event.request.httpVersion ?? "",
            headers: event.request.headers.map(HARNameValue.init),
            queryString: event.queryItems.map(HARNameValue.init),
            cookies: [],
            headersSize: -1,
            bodySize: event.request.bodySize ?? -1,
            postData: event.request.bodyPreview.map {
                HARPostData(
                    mimeType: event.request.mimeType ?? "",
                    text: $0
                )
            }
        )

        let response = HARResponse(
            status: event.response?.statusCode ?? 0,
            statusText: event.response?.statusText ?? "",
            httpVersion: event.response?.httpVersion ?? "",
            headers: event.response?.headers.map(HARNameValue.init) ?? [],
            cookies: [],
            content: .init(
                size: event.response?.bodySize ?? -1,
                mimeType: event.response?.mimeType ?? "",
                text: event.response?.bodyPreview
            ),
            redirectURL: event.response?.redirectURL ?? "",
            headersSize: -1,
            bodySize: event.response?.bodySize ?? -1
        )

        return HAREntry(
            startedDateTime: event.startedAt,
            time: max(0, event.durationMs ?? 0),
            request: request,
            response: response,
            cache: [:],
            timings: .init(send: 0, wait: max(0, event.durationMs ?? 0), receive: 0),
            comment: event.failure.map { "\($0.domain) (\($0.code)): \($0.description)" }
        )
    }
}

private struct HARDocument: Codable {
    let log: HARLog
}

private struct HARLog: Codable {
    let version: String
    let creator: HARCreator
    let entries: [HAREntry]
}

private struct HARCreator: Codable {
    let name: String
    let version: String
}

private struct HAREntry: Codable {
    let startedDateTime: Date
    let time: Double
    let request: HARRequest
    let response: HARResponse
    let cache: [String: String]
    let timings: HARTimings
    let comment: String?
}

private struct HARRequest: Codable {
    let method: String
    let url: String
    let httpVersion: String
    let headers: [HARNameValue]
    let queryString: [HARNameValue]
    let cookies: [HARNameValue]
    let headersSize: Int
    let bodySize: Int
    let postData: HARPostData?
}

private struct HARResponse: Codable {
    let status: Int
    let statusText: String
    let httpVersion: String
    let headers: [HARNameValue]
    let cookies: [HARNameValue]
    let content: HARContent
    let redirectURL: String
    let headersSize: Int
    let bodySize: Int
}

private struct HARContent: Codable {
    let size: Int
    let mimeType: String
    let text: String?
}

private struct HARTimings: Codable {
    let send: Double
    let wait: Double
    let receive: Double
}

private struct HARPostData: Codable {
    let mimeType: String
    let text: String
}

private struct HARNameValue: Codable {
    let name: String
    let value: String

    init(_ pair: NetworkNameValuePair) {
        name = pair.name
        value = pair.value
    }
}
