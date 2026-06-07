import Foundation
import XCTest
@testable import AppReportKitDiagnostics

final class HARExporterTests: XCTestCase {
    func testHARExportIncludesRequiredTopLevelFieldsAndEntryData() throws {
        let exporter = HARExporter(creatorVersion: "0.2.0-test")
        let event = NetworkEvent(
            id: "1",
            timing: .init(
                startedAt: Date(timeIntervalSince1970: 0),
                completedAt: Date(timeIntervalSince1970: 1),
                durationMs: 1000
            ),
            target: .init(
                method: "GET",
                scheme: "https",
                host: "example.com",
                path: "/orders",
                queryItems: [NetworkNameValuePair(name: "token", value: "<redacted>")]
            ),
            request: .init(
                headers: [NetworkNameValuePair(name: "Authorization", value: "<redacted>")],
                bodyPreview: nil,
                bodySize: nil,
                mimeType: nil,
                httpVersion: "HTTP/1.1"
            ),
            response: .init(
                statusCode: 200,
                statusText: "ok",
                headers: [NetworkNameValuePair(name: "Content-Type", value: "application/json")],
                content: .init(
                    bodyPreview: #"{"ok":true}"#,
                    bodySize: 11,
                    mimeType: "application/json"
                ),
                httpVersion: "",
                redirectURL: nil
            ),
            failure: nil,
            taskMetadata: [:]
        )

        let json = try JSONSerialization.jsonObject(with: exporter.export([event])) as? [String: Any]
        let log = try XCTUnwrap(json?["log"] as? [String: Any])
        let creator = try XCTUnwrap(log["creator"] as? [String: Any])
        let entries = try XCTUnwrap(log["entries"] as? [[String: Any]])
        let firstEntry = try XCTUnwrap(entries.first)
        let request = try XCTUnwrap(firstEntry["request"] as? [String: Any])
        let response = try XCTUnwrap(firstEntry["response"] as? [String: Any])

        XCTAssertEqual(log["version"] as? String, "1.2")
        XCTAssertEqual(creator["name"] as? String, "AppReportKitDiagnostics")
        XCTAssertEqual(creator["version"] as? String, "0.2.0-test")
        XCTAssertEqual(request["method"] as? String, "GET")
        XCTAssertEqual(request["url"] as? String, "https://example.com/orders?token=%3Credacted%3E")
        XCTAssertEqual(response["status"] as? Int, 200)
        XCTAssertNotNil(firstEntry["timings"])
    }

    func testHARExportUsesNegativeOneForUnknownSizesAndPreservesFailureMetadata() throws {
        let exporter = HARExporter()
        let event = NetworkEvent(
            id: "failed",
            timing: .init(
                startedAt: Date(timeIntervalSince1970: 0),
                completedAt: Date(timeIntervalSince1970: 1),
                durationMs: 1000
            ),
            target: .init(
                method: "POST",
                scheme: "https",
                host: "example.com",
                path: "/submit",
                queryItems: []
            ),
            request: .init(
                headers: [],
                bodyPreview: nil,
                bodySize: nil,
                mimeType: nil,
                httpVersion: "HTTP/1.1"
            ),
            response: nil,
            failure: .init(domain: "NSURLErrorDomain", code: -1009, description: "offline"),
            taskMetadata: [:]
        )

        let json = try JSONSerialization.jsonObject(with: exporter.export([event])) as? [String: Any]
        let log = try XCTUnwrap(json?["log"] as? [String: Any])
        let entry = try XCTUnwrap((log["entries"] as? [[String: Any]])?.first)
        let request = try XCTUnwrap(entry["request"] as? [String: Any])
        let response = try XCTUnwrap(entry["response"] as? [String: Any])

        XCTAssertEqual(request["bodySize"] as? Int, -1)
        XCTAssertEqual(response["bodySize"] as? Int, -1)
        XCTAssertEqual(entry["comment"] as? String, "NSURLErrorDomain (-1009): offline")
    }

    func testHARExportDoesNotLeakRedactedValues() throws {
        let exporter = HARExporter()
        let event = NetworkEvent(
            id: "1",
            timing: .init(
                startedAt: Date(timeIntervalSince1970: 0),
                completedAt: Date(timeIntervalSince1970: 1),
                durationMs: 1000
            ),
            target: .init(
                method: "GET",
                scheme: "https",
                host: "example.com",
                path: "/orders",
                queryItems: [NetworkNameValuePair(name: "access_token", value: "<redacted>")]
            ),
            request: .init(
                headers: [NetworkNameValuePair(name: "Authorization", value: "<redacted>")],
                bodyPreview: nil,
                bodySize: nil,
                mimeType: nil,
                httpVersion: "HTTP/1.1"
            ),
            response: nil,
            failure: nil,
            taskMetadata: [:]
        )

        let output = try XCTUnwrap(String(data: exporter.export([event]), encoding: .utf8))
        XCTAssertFalse(output.contains("top-secret"))
        XCTAssertTrue(output.contains("<redacted>"))
    }

    func testHARExportPreservesRecordedHTTPVersionsAndLeavesUnknownRequestVersionBlank() throws {
        let exporter = HARExporter()
        let knownVersionEvent = NetworkEvent(
            id: "known",
            timing: .init(
                startedAt: Date(timeIntervalSince1970: 0),
                completedAt: Date(timeIntervalSince1970: 1),
                durationMs: 1000
            ),
            target: .init(
                method: "GET",
                scheme: "https",
                host: "example.com",
                path: "/known",
                queryItems: []
            ),
            request: .init(
                headers: [],
                bodyPreview: nil,
                bodySize: nil,
                mimeType: nil,
                httpVersion: "HTTP/2"
            ),
            response: .init(
                statusCode: 200,
                statusText: "ok",
                headers: [],
                content: .init(),
                httpVersion: "HTTP/2",
                redirectURL: nil
            ),
            failure: nil,
            taskMetadata: [:]
        )
        let unknownVersionEvent = NetworkEvent(
            id: "unknown",
            timing: .init(
                startedAt: Date(timeIntervalSince1970: 0),
                completedAt: Date(timeIntervalSince1970: 1),
                durationMs: 1000
            ),
            target: .init(
                method: "GET",
                scheme: "https",
                host: "example.com",
                path: "/unknown",
                queryItems: []
            ),
            request: .init(
                headers: [],
                bodyPreview: nil,
                bodySize: nil,
                mimeType: nil,
                httpVersion: nil
            ),
            response: .init(
                statusCode: 200,
                statusText: "ok",
                headers: [],
                content: .init(),
                httpVersion: nil,
                redirectURL: nil
            ),
            failure: nil,
            taskMetadata: [:]
        )

        let json = try JSONSerialization.jsonObject(
            with: exporter.export([knownVersionEvent, unknownVersionEvent])
        ) as? [String: Any]
        let entries = try XCTUnwrap(
            ((json?["log"] as? [String: Any])?["entries"] as? [[String: Any]])
        )
        let knownRequest = try XCTUnwrap(entries[0]["request"] as? [String: Any])
        let knownResponse = try XCTUnwrap(entries[0]["response"] as? [String: Any])
        let unknownRequest = try XCTUnwrap(entries[1]["request"] as? [String: Any])
        let unknownResponse = try XCTUnwrap(entries[1]["response"] as? [String: Any])

        XCTAssertEqual(knownRequest["httpVersion"] as? String, "HTTP/2")
        XCTAssertEqual(knownResponse["httpVersion"] as? String, "HTTP/2")
        XCTAssertEqual(unknownRequest["httpVersion"] as? String, "")
        XCTAssertEqual(unknownResponse["httpVersion"] as? String, "")
    }
}
