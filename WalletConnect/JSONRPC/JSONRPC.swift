// Copyright © 2017-2019 Trust Wallet.
//
// This file is part of Trust. The full Trust copyright notice, including
// terms governing use, modification, and redistribution, is contained in the
// file LICENSE at the root of the source code distribution tree.

import Foundation

let JSONRPCVersion = "2.0"

struct JSONRPCError: Error, Codable {
    let code: Int
    let message: String
}

public struct JSONRPCRequest<T: Codable>: Codable {
    public let id: Int64
    let jsonrpc = JSONRPCVersion
    let method: String
    public let params: T
    /**
     Session info
     
     leave it optional make it compatible with the original walletConnect</br>

     this means if connect with original walletConnect, `self.session` is __ALWASY nil__
     */
    public let session: JSONRPCSession?

    public init(id: Int64, method: String, params: T, session: JSONRPCSession? = nil) {
        self.id = id
        self.method = method
        self.params = params
        self.session = session
    }
}

struct JSONRPCResponse<T: Codable>: Codable {
    let jsonrpc = JSONRPCVersion
    let id: Int64
    let result: T

    enum CodingKeys: String, CodingKey {
        case jsonrpc
        case id
        case result
        case error
    }

    init(id: Int64, result: T) {
        self.id = id
        self.result = result
    }
}

struct JSONRPCErrorResponse: Codable {
    let jsonrpc = JSONRPCVersion
    let id: Int64
    let error: JSONRPCError
}

public struct JSONRPCSession: Codable {
    public let chainId: String?
    public let account: String?

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        do {
            chainId = try values.decodeIfPresent(String.self, forKey: .chainId)
        } catch {
            /// compatible with early version
            if let chainIdIntValue = try values.decodeIfPresent(Int.self, forKey: .chainId) {
                chainId = "\(chainIdIntValue)"
            } else {
                chainId = nil
            }
        }
        account = try values.decodeIfPresent(String.self, forKey: .account)
    }
}

extension JSONRPCResponse {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encode(result, forKey: .result)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let error = try values.decodeIfPresent(JSONRPCError.self, forKey: .error) {
            throw error
        }
        self.id = try values.decode(Int64.self, forKey: .id)
        self.result = try values.decode(T.self, forKey: .result)
    }
}

public func generateId() -> Int64 {
    return Int64(Date().timeIntervalSince1970) * 1000
}
