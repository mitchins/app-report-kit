import Foundation

public struct NetworkRedactor: Sendable {
    private let policy: NetworkCapturePolicy
    private let normalizedRedactedKeys: Set<String>

    public init(policy: NetworkCapturePolicy) {
        self.policy = policy
        normalizedRedactedKeys = Set(policy.redactedKeys.map(Self.normalizeRedactionKey))
    }

    public func redactHeaders(_ headers: [AnyHashable: Any]?) -> [NetworkNameValuePair] {
        guard let headers else {
            return []
        }

        return headers.compactMap { key, value in
            guard let headerName = key as? String else {
                return nil
            }

            let headerValue = String(describing: value)
            if shouldRedact(key: headerName) {
                return NetworkNameValuePair(name: headerName, value: "<redacted>")
            }

            return NetworkNameValuePair(name: headerName, value: headerValue)
        }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    public func redactQueryItems(_ items: [URLQueryItem]) -> [NetworkNameValuePair] {
        items.map { item in
            NetworkNameValuePair(
                name: item.name,
                value: shouldRedact(key: item.name) ? "<redacted>" : (item.value ?? "")
            )
        }
    }

    public func redactMetadata(_ metadata: [String: String]) -> [String: String] {
        metadata.reduce(into: [:]) { partialResult, entry in
            partialResult[entry.key] = shouldRedact(key: entry.key) ? "<redacted>" : entry.value
        }
    }

    public func bodyPreview(from data: Data?, contentType: String?, enabled: Bool) -> String? {
        guard enabled, let data, !data.isEmpty else {
            return nil
        }

        guard isPreviewable(contentType: contentType) else {
            return nil
        }

        let lowercasedContentType = (contentType ?? "").lowercased()
        let preview: String

        if lowercasedContentType.contains("application/json") || lowercasedContentType.contains("+json") {
            guard let redactedJSON = redactJSONString(data) else {
                return nil
            }
            preview = redactedJSON
        } else if lowercasedContentType.contains("application/x-www-form-urlencoded") {
            preview = redactFormEncodedString(data)
        } else {
            guard let string = String(data: data, encoding: .utf8) else {
                return nil
            }
            preview = scrubRawText(string)
        }

        return truncate(preview)
    }

    private func redactJSONString(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        let redactedObject = redactJSONValue(object, key: nil)
        guard let encoded = try? JSONSerialization.data(withJSONObject: redactedObject) else {
            return nil
        }

        return String(decoding: encoded, as: UTF8.self)
    }

    private func redactJSONValue(_ value: Any, key: String?) -> Any {
        if let key, shouldRedact(key: key) {
            return "<redacted>"
        }

        switch value {
        case let dictionary as [String: Any]:
            return dictionary.reduce(into: [String: Any]()) { partialResult, entry in
                partialResult[entry.key] = redactJSONValue(entry.value, key: entry.key)
            }
        case let array as [Any]:
            return array.map { redactJSONValue($0, key: nil) }
        default:
            return value
        }
    }

    private func redactFormEncodedString(_ data: Data) -> String {
        guard let string = String(data: data, encoding: .utf8) else {
            return ""
        }

        return string.split(separator: "&").map { pair in
            let components = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard let key = components.first else {
                return String(pair)
            }

            let value = components.count > 1 ? components[1] : ""
            if shouldRedact(key: key) {
                return "\(key)=<redacted>"
            }

            return "\(key)=\(value)"
        }
        .joined(separator: "&")
    }

    private func scrubRawText(_ string: String) -> String {
        var scrubbed = string
        scrubbed = replaceMatches(
            in: scrubbed,
            expression: Self.authorizationExpression,
            template: "$1$2<redacted>"
        )
        scrubbed = replaceMatches(
            in: scrubbed,
            expression: Self.keyValueSecretExpression,
            template: "$1<redacted>"
        )
        scrubbed = replaceMatches(
            in: scrubbed,
            expression: Self.bearerTokenExpression,
            template: "Bearer <redacted>"
        )
        scrubbed = replaceMatches(
            in: scrubbed,
            expression: Self.jwtExpression,
            template: "<redacted>"
        )
        return scrubbed
    }

    private func replaceMatches(
        in string: String,
        expression: NSRegularExpression?,
        template: String
    ) -> String {
        guard let expression else {
            return string
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return expression.stringByReplacingMatches(
            in: string,
            options: [],
            range: range,
            withTemplate: template
        )
    }

    private func truncate(_ string: String) -> String {
        let bytes = Array(string.utf8)
        guard bytes.count > policy.maxBodyPreviewBytes else {
            return string
        }

        return String(decoding: bytes.prefix(policy.maxBodyPreviewBytes), as: UTF8.self)
    }

    private func shouldRedact(key: String) -> Bool {
        let lowercased = key.lowercased()
        return policy.redactedKeys.contains(lowercased)
            || normalizedRedactedKeys.contains(Self.normalizeRedactionKey(lowercased))
    }

    private static func normalizeRedactionKey(_ key: String) -> String {
        let filteredScalars = key.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        return String(String.UnicodeScalarView(filteredScalars)).lowercased()
    }

    private func isPreviewable(contentType: String?) -> Bool {
        let lowercased = (contentType ?? "").lowercased()
        if lowercased.isEmpty {
            return true
        }

        let blockedPrefixes = ["image/", "video/", "audio/", "multipart/"]
        if blockedPrefixes.contains(where: { lowercased.hasPrefix($0) }) {
            return false
        }

        if lowercased.contains("octet-stream") || lowercased.contains("application/pdf") {
            return false
        }

        return true
    }

    private static let bearerTokenExpression = makeRegularExpression(
        pattern: #"(?i)Bearer\s+[A-Za-z0-9\-._~+/]+=*"#
    )

    private static let authorizationExpression = makeRegularExpression(
        pattern: #"(?i)(\"?authorization\"?\s*[:=]\s*)(Bearer\s+)?([^\r\n,}]+)"#
    )

    private static let keyValueSecretExpression = makeRegularExpression(
        pattern: #"(?i)(\"?(api[_-]?key|access[_-]?token|refresh[_-]?token|id[_-]?token|token|secret|password|session)\"?\s*[:=]\s*[\"']?)[^\s\"'&,}]+"#
    )

    private static let jwtExpression = makeRegularExpression(
        pattern: #"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9._-]+\.[A-Za-z0-9._-]+\b"#
    )

    private static func makeRegularExpression(pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern)
    }
}
