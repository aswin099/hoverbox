import Foundation
import HoverboxCore
import Security
import UniformTypeIdentifiers

/// Upload secrets (S3 secret keys, WebDAV passwords) live in the login Keychain, one item per
/// destination, never in preferences.
enum UploadSecrets {
    private static let service = "com.arcova.hoverbox.uploads"

    static func secret(for id: UUID) -> String? {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                      kSecAttrAccount: id.uuidString, kSecReturnData: true,
                                      kSecMatchLimit: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setSecret(_ secret: String, for id: UUID) {
        let match: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                      kSecAttrAccount: id.uuidString]
        guard !secret.isEmpty else {
            SecItemDelete(match as CFDictionary)
            return
        }
        let data = Data(secret.utf8)
        if SecItemUpdate(match as CFDictionary, [kSecValueData: data] as CFDictionary) == errSecItemNotFound {
            var item = match
            item[kSecValueData] = data
            item[kSecAttrLabel] = "Hoverbox upload key"
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}

/// Sends files to the user's own storage. The only network code in Hoverbox, and it only ever
/// talks to destinations the user set up. Blocking; call it off the main thread.
enum Uploader {
    static let maximumSize: Int64 = 5 * 1024 * 1024 * 1024

    /// Uploads each file and returns a record with its share link.
    static func upload(_ files: [URL], to destination: UploadDestination) throws -> [UploadRecord] {
        let secret = UploadSecrets.secret(for: destination.id) ?? ""
        return try files.map { file in
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            guard size <= maximumSize else { throw UploadError.tooLarge }
            let type = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            switch destination.kind {
            case .s3(let settings):
                let key = UploadPlanner.objectName(for: file.lastPathComponent, prefix: settings.prefix)
                let request = try UploadPlanner.s3Upload(settings, secret: secret, key: key,
                                                         payloadHash: try SigV4.sha256Hex(fileAt: file), contentType: type)
                try send(request, file: file)
                let link = try UploadPlanner.s3Link(settings, secret: secret, key: key, lifetime: destination.linkLifetime)
                return UploadRecord(fileName: file.lastPathComponent, link: link.link, objectURL: request.url!,
                                    destinationID: destination.id, expiresAt: link.expires)
            case .webDAV(let settings):
                // A random prefix keeps names from colliding in the shared folder.
                let name = UploadPlanner.randomToken().prefix(6) + "-" + file.lastPathComponent
                let request = try UploadPlanner.webDAVUpload(settings, password: secret, fileName: String(name), contentType: type)
                try send(request, file: file)
                return UploadRecord(fileName: file.lastPathComponent,
                                    link: UploadPlanner.webDAVLink(settings, fileURL: request.url!, fileName: String(name)),
                                    objectURL: request.url!, destinationID: destination.id)
            }
        }
    }

    /// Removes an uploaded file from the server.
    static func delete(_ record: UploadRecord, from destination: UploadDestination) throws {
        let secret = UploadSecrets.secret(for: destination.id) ?? ""
        switch destination.kind {
        case .s3(let settings): try send(try UploadPlanner.s3Delete(settings, secret: secret, objectURL: record.objectURL))
        case .webDAV(let settings): try send(UploadPlanner.webDAVDelete(settings, password: secret, objectURL: record.objectURL))
        }
    }

    /// Uploads a tiny file and removes it again, to check the settings and keys.
    static func test(_ destination: UploadDestination) throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("hoverbox-connection-test.txt")
        try Data("Hoverbox connection test. Safe to delete.\n".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let records = try upload([file], to: destination)
        try records.forEach { try delete($0, from: destination) }
    }

    private static func send(_ request: URLRequest, file: URL? = nil) throws {
        var request = request
        request.timeoutInterval = 120
        let done = DispatchSemaphore(value: 0)
        let box = ResponseBox()
        let completion: @Sendable (Data?, URLResponse?, Error?) -> Void = { data, response, error in
            box.value = (data, response, error)
            done.signal()
        }
        let task = file.map { URLSession.shared.uploadTask(with: request, fromFile: $0, completionHandler: completion) }
            ?? URLSession.shared.dataTask(with: request, completionHandler: completion)
        task.resume()
        done.wait()
        let outcome = box.value
        if let error = outcome.2 { throw error }
        let status = (outcome.1 as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw UploadError.server(status: status, message: serverMessage(outcome.0))
        }
    }

    /// The readable part of an S3 or WebDAV error body, if any.
    private static func serverMessage(_ data: Data?) -> String {
        guard let text = data.flatMap({ String(data: $0, encoding: .utf8) }) else { return "" }
        if let start = text.range(of: "<Message>"), let end = text.range(of: "</Message>", range: start.upperBound..<text.endIndex) {
            return String(text[start.upperBound..<end.lowerBound])
        }
        return text.count < 200 ? text.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }
}

private final class ResponseBox: @unchecked Sendable {
    var value: (Data?, URLResponse?, Error?) = (nil, nil, nil)
}
