import Foundation

public struct FeedbackAttachment: Codable, Equatable {
    public let filename: String
    public let contentType: String
    public let byteCount: Int
    public let dataBase64: String?
    public let url: String?
    public let sha256: String?

    public init(
        filename: String,
        contentType: String,
        byteCount: Int,
        dataBase64: String? = nil,
        url: String? = nil,
        sha256: String? = nil
    ) {
        self.filename = filename
        self.contentType = contentType
        self.byteCount = byteCount
        self.dataBase64 = dataBase64
        self.url = url
        self.sha256 = sha256
    }

    public init(
        filename: String,
        contentType: String,
        data: Data,
        url: String? = nil,
        sha256: String? = nil
    ) {
        self.init(
            filename: filename,
            contentType: contentType,
            byteCount: data.count,
            dataBase64: data.base64EncodedString(),
            url: url,
            sha256: sha256
        )
    }
}

