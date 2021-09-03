// Copyright © 2017-2019 Trust Wallet.
//
// This file is part of Trust. The full Trust copyright notice, including
// terms governing use, modification, and redistribution, is contained in the
// file LICENSE at the root of the source code distribution tree.

import Foundation

public struct WCEncryptionPayload: Codable {
    public let data: String
    public let hmac: String
    public let iv: String

    public init(data: String, hmac: String, iv: String) {
        self.data = data
        self.hmac = hmac
        self.iv = iv
    }
}

public enum WCSocketMessageType: String, Codable {
    case pub
    case sub
    case ack
}

public struct WCSocketMessage<T: Codable>: Codable {
    public let topic: String
    public let type: WCSocketMessageType
    public let payload: T
    public let timestamp: UInt64?
}

public extension WCEncryptionPayload {
    static func extract(_ string: String) -> (topic: String,
                                              messageType: WCSocketMessageType,
                                              payload: WCEncryptionPayload?,
                                              timestamp: UInt64?)? {
        guard let data = string.data(using: .utf8) else {
            return nil
        }
        do {
            let decoder = JSONDecoder()
            if let message = try? decoder.decode(WCSocketMessage<WCEncryptionPayload>.self, from: data) {
                return (message.topic, message.type, message.payload, message.timestamp)
            } else {
                let message = try decoder.decode(WCSocketMessage<String>.self, from: data)
                let payload: WCEncryptionPayload?
                if !message.payload.isEmpty {
                    let payloadData = message.payload.data(using: .utf8)
                    payload = try decoder.decode(WCEncryptionPayload.self, from: payloadData!)
                } else {
                    payload = nil
                }
                return  (message.topic, message.type, payload, message.timestamp)
            }
        } catch let error {
            print(error)
        }
        return nil
    }
}
