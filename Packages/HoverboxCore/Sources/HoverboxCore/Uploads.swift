import CryptoKit
import Foundation

/// Somewhere the user uploads to: their own S3-compatible bucket or WebDAV folder.
/// Secrets (the S3 secret key, the WebDAV password) are not stored here; the app keeps
/// them in the Keychain under the destination's id.
public struct UploadDestination: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
        case s3(S3Settings)
        case webDAV(WebDAVSettings)
    }

    public let id: UUID
    public var name: String
    public var kind: Kind
    /// How long links to private files stay valid (S3 without a public URL only).
    public var linkLifetime: TimeInterval

    public init(id: UUID = UUID(), name: String, kind: Kind, linkLifetime: TimeInterval = 86_400) {
        self.id = id
        self.name = name
        self.kind = kind
        self.linkLifetime = linkLifetime
    }
}

/// Amazon S3, Cloudflare R2, Backblaze B2, MinIO and anything else that speaks S3.
public struct S3Settings: Codable, Equatable, Sendable {
    /// For example https://s3.us-east-1.amazonaws.com or https://<account>.r2.cloudflarestorage.com
    public var endpoint: String
    /// "auto" for R2.
    public var region: String
    public var bucket: String
    public var accessKeyID: String
    /// Folder inside the bucket, such as "shared".
    public var prefix: String
    /// If the bucket is public or behind a custom domain, links use this instead of expiring ones.
    public var publicBaseURL: String

    public init(endpoint: String, region: String, bucket: String, accessKeyID: String,
                prefix: String = "", publicBaseURL: String = "") {
        self.endpoint = endpoint
        self.region = region
        self.bucket = bucket
        self.accessKeyID = accessKeyID
        self.prefix = prefix
        self.publicBaseURL = publicBaseURL
    }
}

/// Nextcloud, ownCloud, many NAS boxes and web hosts.
public struct WebDAVSettings: Codable, Equatable, Sendable {
    /// The folder to upload into, such as https://cloud.example.com/remote.php/dav/files/me/Shared
    public var folderURL: String
    public var username: String
    /// Where the uploaded files can be read from, if not the WebDAV address itself.
    public var publicBaseURL: String

    public init(folderURL: String, username: String, publicBaseURL: String = "") {
        self.folderURL = folderURL
        self.username = username
        self.publicBaseURL = publicBaseURL
    }
}

public enum UploadError: LocalizedError, Equatable {
    case badSettings(String)
    case server(status: Int, message: String)
    case tooLarge

    public var errorDescription: String? {
        switch self {
        case .badSettings(let detail): return "The upload settings aren't complete: \(detail)."
        case .server(let status, let message):
            let detail = message.isEmpty ? "" : ": \(message)"
            switch status {
            case 401, 403: return "The storage refused the upload (check the keys or password)\(detail)"
            case 404: return "The bucket or folder wasn't found\(detail)"
            default: return "The upload failed (HTTP \(status))\(detail)"
            }
        case .tooLarge: return "Files over 5 GB can't be uploaded yet."
        }
    }
}

/// One uploaded file, for the history in the menu bar.
public struct UploadRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var fileName: String
    public var link: URL
    /// Where to send a DELETE to remove it again.
    public var objectURL: URL
    public var destinationID: UUID
    public var uploadedAt: Date
    public var expiresAt: Date?

    public init(id: UUID = UUID(), fileName: String, link: URL, objectURL: URL, destinationID: UUID,
                uploadedAt: Date = Date(), expiresAt: Date? = nil) {
        self.id = id
        self.fileName = fileName
        self.link = link
        self.objectURL = objectURL
        self.destinationID = destinationID
        self.uploadedAt = uploadedAt
        self.expiresAt = expiresAt
    }
}

// MARK: - Request building

/// Builds the HTTP requests for an upload, its share link and its removal. Pure, so it can be
/// tested without a network; the app sends the requests.
public enum UploadPlanner {
    /// A short random folder per upload, so names never collide and links can't be guessed.
    public static func objectName(for fileName: String, prefix: String, token: String = randomToken()) -> String {
        let folder = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return (folder.isEmpty ? "" : folder + "/") + token + "/" + fileName
    }

    public static func randomToken() -> String {
        let letters = Array("abcdefghijkmnpqrstuvwxyz23456789")
        return String((0..<10).map { _ in letters.randomElement()! })
    }

    /// The URL of an object in an S3 bucket (path style, which every S3-compatible service accepts).
    public static func s3ObjectURL(_ settings: S3Settings, key: String) throws -> URL {
        let endpoint = settings.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !settings.bucket.isEmpty else { throw UploadError.badSettings("no bucket") }
        guard let base = URL(string: endpoint), base.scheme == "https" || base.scheme == "http", base.host != nil else {
            throw UploadError.badSettings("the endpoint should look like https://s3.example.com")
        }
        return base.appendingPathComponent(settings.bucket).appendingPathComponent(key)
    }

    /// The signed PUT for an S3 upload.
    public static func s3Upload(_ settings: S3Settings, secret: String, key: String, payloadHash: String,
                                contentType: String, date: Date = Date()) throws -> URLRequest {
        var request = URLRequest(url: try s3ObjectURL(settings, key: key))
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        try SigV4.sign(&request, settings: settings, secret: secret, payloadHash: payloadHash, date: date)
        return request
    }

    /// The signed DELETE that removes an uploaded object.
    public static func s3Delete(_ settings: S3Settings, secret: String, objectURL: URL, date: Date = Date()) throws -> URLRequest {
        var request = URLRequest(url: objectURL)
        request.httpMethod = "DELETE"
        try SigV4.sign(&request, settings: settings, secret: secret, payloadHash: SigV4.emptyPayloadHash, date: date)
        return request
    }

    /// The link to share: a permanent public one if configured, else an expiring signed link.
    public static func s3Link(_ settings: S3Settings, secret: String, key: String, lifetime: TimeInterval,
                              date: Date = Date()) throws -> (link: URL, expires: Date?) {
        let base = settings.publicBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if !base.isEmpty, let url = URL(string: base) {
            return (url.appendingPathComponent(key), nil)
        }
        let seconds = Int(min(max(lifetime, 60), 604_800))  // S3 allows up to 7 days
        let url = try SigV4.presign(try s3ObjectURL(settings, key: key), settings: settings, secret: secret,
                                    expires: seconds, date: date)
        return (url, date.addingTimeInterval(TimeInterval(seconds)))
    }

    /// The PUT for a WebDAV upload, with the password as HTTP basic authentication.
    public static func webDAVUpload(_ settings: WebDAVSettings, password: String, fileName: String,
                                    contentType: String) throws -> URLRequest {
        var request = URLRequest(url: try webDAVFileURL(settings, fileName: fileName))
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuth(settings.username, password), forHTTPHeaderField: "Authorization")
        return request
    }

    public static func webDAVDelete(_ settings: WebDAVSettings, password: String, objectURL: URL) -> URLRequest {
        var request = URLRequest(url: objectURL)
        request.httpMethod = "DELETE"
        request.setValue(basicAuth(settings.username, password), forHTTPHeaderField: "Authorization")
        return request
    }

    public static func webDAVFileURL(_ settings: WebDAVSettings, fileName: String) throws -> URL {
        let folder = settings.folderURL.trimmingCharacters(in: CharacterSet(charactersIn: " "))
        guard let base = URL(string: folder), base.scheme == "https" || base.scheme == "http", base.host != nil else {
            throw UploadError.badSettings("the folder address should look like https://cloud.example.com/…")
        }
        return base.appendingPathComponent(fileName)
    }

    public static func webDAVLink(_ settings: WebDAVSettings, fileURL: URL, fileName: String) -> URL {
        let base = settings.publicBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if !base.isEmpty, let url = URL(string: base) { return url.appendingPathComponent(fileName) }
        return fileURL
    }

    private static func basicAuth(_ user: String, _ password: String) -> String {
        "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
    }
}

// MARK: - AWS Signature Version 4

/// Signs S3 requests the way AWS, R2, B2 and MinIO expect (Signature Version 4).
public enum SigV4 {
    public static let emptyPayloadHash = sha256Hex(Data())
    public static let unsignedPayload = "UNSIGNED-PAYLOAD"

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Hashes a file in chunks, so large files don't need to fit in memory.
    public static func sha256Hex(fileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Adds x-amz-date, x-amz-content-sha256, Host and Authorization to `request`.
    public static func sign(_ request: inout URLRequest, settings: S3Settings, secret: String,
                            payloadHash: String, date: Date) throws {
        guard let url = request.url, let host = hostHeader(url) else { throw UploadError.badSettings("no endpoint") }
        guard !settings.accessKeyID.isEmpty, !secret.isEmpty else { throw UploadError.badSettings("no access keys") }
        let (amzDate, day) = timestamps(date)
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")

        let headers = (request.allHTTPHeaderFields ?? [:])
            .map { (name: $0.key.lowercased(), value: $0.value.trimmingCharacters(in: .whitespaces)) }
            .filter { $0.name != "authorization" && $0.name != "content-length" && $0.name != "user-agent" }
            .sorted { $0.name < $1.name }
        let signedHeaders = headers.map(\.name).joined(separator: ";")
        let canonical = [request.httpMethod ?? "GET", canonicalPath(url), canonicalQuery(url),
                         headers.map { "\($0.name):\($0.value)\n" }.joined(), signedHeaders, payloadHash]
            .joined(separator: "\n")
        let scope = "\(day)/\(settings.region)/s3/aws4_request"
        let signature = signatureHex(secret: secret, day: day, region: settings.region,
                                     stringToSign: stringToSign(amzDate: amzDate, scope: scope, canonical: canonical))
        request.setValue("AWS4-HMAC-SHA256 Credential=\(settings.accessKeyID)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)",
                         forHTTPHeaderField: "Authorization")
    }

    /// A GET link that works without credentials until it expires.
    public static func presign(_ url: URL, settings: S3Settings, secret: String, expires: Int, date: Date) throws -> URL {
        guard let host = hostHeader(url) else { throw UploadError.badSettings("no endpoint") }
        guard !settings.accessKeyID.isEmpty, !secret.isEmpty else { throw UploadError.badSettings("no access keys") }
        let (amzDate, day) = timestamps(date)
        let scope = "\(day)/\(settings.region)/s3/aws4_request"
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.percentEncodedQueryItems = [
            URLQueryItem(name: "X-Amz-Algorithm", value: "AWS4-HMAC-SHA256"),
            URLQueryItem(name: "X-Amz-Credential", value: encode("\(settings.accessKeyID)/\(scope)")),
            URLQueryItem(name: "X-Amz-Date", value: amzDate),
            URLQueryItem(name: "X-Amz-Expires", value: String(expires)),
            URLQueryItem(name: "X-Amz-SignedHeaders", value: "host"),
        ]
        let unsigned = components.url!
        let canonical = ["GET", canonicalPath(unsigned), canonicalQuery(unsigned), "host:\(host)\n", "host", unsignedPayload]
            .joined(separator: "\n")
        let signature = signatureHex(secret: secret, day: day, region: settings.region,
                                     stringToSign: stringToSign(amzDate: amzDate, scope: scope, canonical: canonical))
        components.percentEncodedQueryItems?.append(URLQueryItem(name: "X-Amz-Signature", value: signature))
        return components.url!
    }

    // MARK: Pieces

    static func timestamps(_ date: Date) -> (amzDate: String, day: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = formatter.string(from: date)
        return (amzDate, String(amzDate.prefix(8)))
    }

    static func hostHeader(_ url: URL) -> String? {
        guard let host = url.host else { return nil }
        if let port = url.port, !(url.scheme == "https" && port == 443), !(url.scheme == "http" && port == 80) {
            return "\(host):\(port)"
        }
        return host
    }

    /// URI-encodes each path segment once, keeping the slashes (S3's rule).
    static func canonicalPath(_ url: URL) -> String {
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? url.path
        guard !path.isEmpty else { return "/" }
        return path.split(separator: "/", omittingEmptySubsequences: false).map { encode(String($0)) }.joined(separator: "/")
    }

    static func canonicalQuery(_ url: URL) -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems ?? []
        let pairs: [(name: String, value: String)] = items.map { ($0.name, $0.value ?? "") }
        let sorted = pairs.sorted { left, right in
            left.name == right.name ? left.value < right.value : left.name < right.name
        }
        return sorted.map { "\($0.name)=\($0.value)" }.joined(separator: "&")
    }

    static func encode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        // Only ASCII letters and digits count as unreserved.
        return text.unicodeScalars.map { scalar -> String in
            if scalar.isASCII, allowed.contains(scalar) { return String(scalar) }
            return String(scalar).utf8.map { String(format: "%%%02X", $0) }.joined()
        }.joined()
    }

    static func stringToSign(amzDate: String, scope: String, canonical: String) -> String {
        ["AWS4-HMAC-SHA256", amzDate, scope, sha256Hex(Data(canonical.utf8))].joined(separator: "\n")
    }

    static func signatureHex(secret: String, day: String, region: String, stringToSign: String) -> String {
        func hmac(_ key: Data, _ text: String) -> Data {
            Data(HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: SymmetricKey(data: key)))
        }
        var key = hmac(Data("AWS4\(secret)".utf8), day)
        key = hmac(key, region)
        key = hmac(key, "s3")
        key = hmac(key, "aws4_request")
        return hmac(key, stringToSign).map { String(format: "%02x", $0) }.joined()
    }
}
