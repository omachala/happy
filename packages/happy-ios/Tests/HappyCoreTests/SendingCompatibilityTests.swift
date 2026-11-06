import Foundation
import XCTest
@testable import HappyCore
import HappyStore
import HappyWire

final class SendingCompatibilityTests: XCTestCase {
    func testAdditionalMetaKeysSurviveWireEncodingAfterKnownFields() throws {
        let payload: JSONValue = .object([
            "role": .string("user"),
            "meta": .object([
                "sentFrom": .string("ios"),
                "zExtra": .bool(true),
                "aExtra": .null,
                "quote\"Extra": .string("value"),
            ]),
        ])
        let bytes = try UserMessageEncoder.wireBytes(payload)
        XCTAssertEqual(try JSONValue.decode(bytes), payload)
        XCTAssertEqual(
            String(decoding: bytes, as: UTF8.self),
            #"{"role":"user","meta":{"sentFrom":"ios","aExtra":null,"quote\"Extra":"value","zExtra":true}}"#
        )
    }

    func testHappyAppFileEventsByteForByte() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "file-events", withExtension: "json", subdirectory: "Fixtures"))
        let cases = try XCTUnwrap(JSONValue.decode(Data(contentsOf: url)).arrayValue)
        for test in cases {
            let attachment = AttachmentRecord(
                localId: "local", sessionId: "s", path: "local", name: test["name"]!.stringValue!,
                mimeType: "", size: Int(test["size"]!.numberValue!), width: Int(test["width"]!.numberValue!),
                height: Int(test["height"]!.numberValue!), thumbhash: test["thumbhash"]?.stringValue, createdAt: 123
            )
            let result = LegacySyncEngine.filePayload(id: "event-id", time: 123, attachment: attachment, ref: "blob-ref")
            XCTAssertEqual(try result.encoded(), Data(test["canonical"]!.stringValue!.utf8))
            XCTAssertEqual(try UserMessageEncoder.wireBytes(result), Data(test["wire"]!.stringValue!.utf8))
        }
    }

    /// happy-app's own bytes for every case the fork leaves alone (Happy
    /// Agent's); a Happy CLI session's mode meta is the fork's
    /// (messageMeta.ts `resolveMessageModeMeta`): the never-ask permission
    /// whatever was picked, the model and effort picked, overridden or
    /// defaulted. Everything else stays byte for byte.
    static let forkModeMeta: [String: [String: JSONValue]] = [
        "plain": ["permissionMode": .string("bypassPermissions"), "model": .string("claude-opus-5-5"), "effort": .string("high")],
        "codex-default": ["permissionMode": .string("yolo"), "model": .string("gpt-6.1-sol"), "effort": .string("medium")],
        "codex-old": ["permissionMode": .string("yolo"), "model": .string("gpt-6.1-sol"), "effort": .string("medium")],
        "agy": ["permissionMode": .string("yolo"), "model": .string("Gemini 3.8 Flash"), "effort": .string("medium")],
        "null-model-retired": ["permissionMode": .string("bypassPermissions"), "model": .null, "effort": .string("high")],
        "overrides": ["permissionMode": .string("bypassPermissions"), "model": .string("claude-opus-5-5"), "effort": .string("max")],
        "refuse-auto": ["permissionMode": .string("bypassPermissions"), "model": .string("claude-opus-5-5"), "effort": .string("high")],
        "build-version": ["permissionMode": .string("yolo"), "model": .string("gpt-6.1-sol"), "effort": .string("medium")],
    ]

    func testActualHappyAppMetadataAndWireBytes() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "sending", withExtension: "json", subdirectory: "Fixtures"))
        let cases = try XCTUnwrap(JSONValue.decode(Data(contentsOf: url)).arrayValue)
        var forked = 0
        for test in cases {
            let name = test["name"]!.stringValue!
            var session = SessionRecord(
                id: "s", seq: 0, createdAt: 0, updatedAt: 0, active: true, activeAt: 0, projectId: nil,
                metadataVersion: 1, metadataCipher: "", metadata: test["metadata"], agentStateVersion: 1,
                agentStateCipher: nil, agentState: test["agentState"], dataKeyCipher: nil, decryptable: true
            )
            session.thinking = test["thinking"]?.boolValue ?? false
            let message = OutgoingMessage(text: test["text"]!.stringValue!, displayText: test["displayText"]?.stringValue, source: test["source"]?.stringValue == "new_session" ? .newSession : .chat)
            // The fork refuses nothing: every Happy CLI message is forced
            // to the never-ask mode, which every CLI parses.
            let result = try UserMessageEncoder.encode(
                message, session: session, composer: test["composer"]!, settings: test["settings"],
                hasPendingUserMessage: test["pending"]?.boolValue ?? false,
                sentFrom: test["sentFrom"]?.stringValue ?? "ios"
            )
            if let fork = Self.forkModeMeta[name] {
                forked += 1
                let meta = try XCTUnwrap(result["meta"]?.objectValue, name)
                for key in ["permissionMode", "model", "effort"] {
                    XCTAssertEqual(meta[key], fork[key], "\(name) \(key)")
                }
                guard let canonical = test["canonical"]?.stringValue else { continue }
                // The rest is happy-app's, byte for byte.
                var expected = try JSONValue.decode(Data(canonical.utf8))
                var expectedMeta = expected["meta"]?.objectValue ?? [:]
                expectedMeta.merge(fork) { _, value in value }
                expected = .object((expected.objectValue ?? [:]).merging(["meta": .object(expectedMeta)]) { _, value in value })
                XCTAssertEqual(try result.encoded(), try expected.encoded(), name)
                XCTAssertEqual(try UserMessageEncoder.wireBytes(result), try UserMessageEncoder.wireBytes(expected), name)
                continue
            }
            XCTAssertNil(test["error"], name)
            XCTAssertEqual(try result.encoded(), Data(test["canonical"]!.stringValue!.utf8), name)
            XCTAssertEqual(try UserMessageEncoder.wireBytes(result), Data(test["wire"]!.stringValue!.utf8), name)
        }
        XCTAssertEqual(forked, Self.forkModeMeta.count, "every fork case is in the fixture")
    }
}
