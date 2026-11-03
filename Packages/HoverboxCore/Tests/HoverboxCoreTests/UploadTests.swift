import XCTest
@testable import HoverboxCore

final class UploadTests: XCTestCase {
    // Amazon's documented example credentials and time (S3 API reference, "Signature Version 4" examples).
    private let settings = S3Settings(endpoint: "https://examplebucket.s3.amazonaws.com", region: "us-east-1",
                                      bucket: "examplebucket", accessKeyID: "AKIAIOSFODNN7EXAMPLE")
    private let secret = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    private let date = Date(timeIntervalSince1970: 1_369_353_600)  // 2013-05-24 00:00:00 UTC

    private func signature(_ request: URLRequest) -> String? {
        request.value(forHTTPHeaderField: "Authorization")?.components(separatedBy: "Signature=").last
    }

    func testGetObjectExample() throws {
        var request = URLRequest(url: URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!)
        request.setValue("bytes=0-9", forHTTPHeaderField: "Range")
        try SigV4.sign(&request, settings: settings, secret: secret, payloadHash: SigV4.emptyPayloadHash, date: date)
        XCTAssertEqual(signature(request), "f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")!
            .contains("SignedHeaders=host;range;x-amz-content-sha256;x-amz-date"))
    }

    func testPutObjectExample() throws {
        var request = URLRequest(url: URL(string: "https://examplebucket.s3.amazonaws.com/test$file.text")!)
        request.httpMethod = "PUT"
        request.setValue("Fri, 24 May 2013 00:00:00 GMT", forHTTPHeaderField: "Date")
        request.setValue("REDUCED_REDUNDANCY", forHTTPHeaderField: "x-amz-storage-class")
        let hash = SigV4.sha256Hex(Data("Welcome to Amazon S3.".utf8))
        XCTAssertEqual(hash, "44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072")
        try SigV4.sign(&request, settings: settings, secret: secret, payloadHash: hash, date: date)
        XCTAssertEqual(signature(request), "98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd")
    }

    func testPresignedURLExample() throws {
        let url = try SigV4.presign(URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!,
                                    settings: settings, secret: secret, expires: 86_400, date: date)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "X-Amz-Signature" }?.value,
                       "aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404")
        XCTAssertEqual(query.first { $0.name == "X-Amz-Expires" }?.value, "86400")
    }

    func testHashingAFileMatchesHashingItsData() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hash-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data((0..<(9 << 20)).map { UInt8($0 % 251) })  // larger than one read chunk
        try data.write(to: url)
        XCTAssertEqual(try SigV4.sha256Hex(fileAt: url), SigV4.sha256Hex(data))
    }

    // MARK: Planning

    func testObjectNamesAreNestedAndRandom() {
        XCTAssertEqual(UploadPlanner.objectName(for: "a b.pdf", prefix: "/shared/", token: "tok"), "shared/tok/a b.pdf")
        XCTAssertEqual(UploadPlanner.objectName(for: "x.png", prefix: "", token: "tok"), "tok/x.png")
        XCTAssertNotEqual(UploadPlanner.randomToken(), UploadPlanner.randomToken())
    }

    func testS3URLsAreEncodedPathStyle() throws {
        let r2 = S3Settings(endpoint: "https://acct.r2.cloudflarestorage.com/", region: "auto", bucket: "files",
                            accessKeyID: "AK", prefix: "hb")
        let request = try UploadPlanner.s3Upload(r2, secret: "s", key: "hb/tok/a b.pdf", payloadHash: SigV4.emptyPayloadHash,
                                                 contentType: "application/pdf", date: date)
        XCTAssertEqual(request.url?.absoluteString, "https://acct.r2.cloudflarestorage.com/files/hb/tok/a%20b.pdf")
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")!.contains("/auto/s3/aws4_request"))
    }

    func testLinksArePublicOrExpiring() throws {
        var s3 = settings
        let expiring = try UploadPlanner.s3Link(s3, secret: secret, key: "tok/a.pdf", lifetime: 3600, date: date)
        XCTAssertTrue(expiring.link.absoluteString.contains("X-Amz-Signature="))
        XCTAssertEqual(expiring.expires, date.addingTimeInterval(3600))
        let capped = try UploadPlanner.s3Link(s3, secret: secret, key: "tok/a.pdf", lifetime: 30 * 86_400, date: date)
        XCTAssertEqual(capped.expires, date.addingTimeInterval(604_800))

        s3.publicBaseURL = "https://files.example.com/"
        let permanent = try UploadPlanner.s3Link(s3, secret: secret, key: "tok/a b.pdf", lifetime: 3600, date: date)
        XCTAssertEqual(permanent.link.absoluteString, "https://files.example.com/tok/a%20b.pdf")
        XCTAssertNil(permanent.expires)
    }

    func testBadSettingsAreExplained() {
        var s3 = settings
        s3.endpoint = "examplebucket"
        XCTAssertThrowsError(try UploadPlanner.s3ObjectURL(s3, key: "k"))
        s3 = settings
        s3.accessKeyID = ""
        XCTAssertThrowsError(try UploadPlanner.s3Upload(s3, secret: secret, key: "k", payloadHash: "", contentType: "x"))
        XCTAssertThrowsError(try UploadPlanner.webDAVFileURL(WebDAVSettings(folderURL: "nope", username: "u"), fileName: "a"))
    }

    func testWebDAVRequestsAndLinks() throws {
        let dav = WebDAVSettings(folderURL: "https://cloud.example.com/dav/Shared", username: "me")
        let request = try UploadPlanner.webDAVUpload(dav, password: "pw", fileName: "a b.txt", contentType: "text/plain")
        XCTAssertEqual(request.url?.absoluteString, "https://cloud.example.com/dav/Shared/a%20b.txt")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic " + Data("me:pw".utf8).base64EncodedString())
        XCTAssertEqual(UploadPlanner.webDAVLink(dav, fileURL: request.url!, fileName: "a b.txt"), request.url)
        var linked = dav
        linked.publicBaseURL = "https://share.example.com/s"
        XCTAssertEqual(UploadPlanner.webDAVLink(linked, fileURL: request.url!, fileName: "a b.txt").absoluteString,
                       "https://share.example.com/s/a%20b.txt")
    }

    func testDestinationsAndRecordsEncode() throws {
        let destinations = [UploadDestination(name: "R2", kind: .s3(settings), linkLifetime: 3600),
                            UploadDestination(name: "Nextcloud", kind: .webDAV(WebDAVSettings(folderURL: "https://x/y", username: "u")))]
        XCTAssertEqual(try JSONDecoder().decode([UploadDestination].self, from: JSONEncoder().encode(destinations)), destinations)
        let record = UploadRecord(fileName: "a.pdf", link: URL(string: "https://x/a.pdf")!, objectURL: URL(string: "https://x/a.pdf")!,
                                  destinationID: destinations[0].id, expiresAt: date)
        XCTAssertEqual(try JSONDecoder().decode(UploadRecord.self, from: JSONEncoder().encode(record)), record)
    }
}
