// Copyright © 2017-2019 Trust Wallet.
//
// This file is part of Trust. The full Trust copyright notice, including
// terms governing use, modification, and redistribution, is contained in the
// file LICENSE at the root of the source code distribution tree.

import Foundation

//MARK: - session request
public protocol WCSessionRequestParamType: Codable { }
public struct WCSessionRequestParam: WCSessionRequestParamType {
    public let peerId: String
    public let peerMeta: WCPeerMeta
    public let chainId: Int?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        peerId = try container.decode(String.self, forKey: .peerId)
        peerMeta = try container.decode(WCPeerMeta.self, forKey: .peerMeta)
        if let stringChainId = try? container.decodeIfPresent(String.self, forKey: .chainId) {
            chainId = Int(stringChainId)
        } else {
            chainId = try container.decode(Int?.self, forKey: .chainId)
        }
    }
}

//MARK: - session update
public protocol WCSessionUpdateParamType: Codable { }
public struct WCSessionUpdateParam: WCSessionUpdateParamType {
    public let approved: Bool
    public let chainId: Int?
    public let accounts: [String]?

    public init(approved: Bool, chainId: Int?, accounts: [String]?) {
        self.approved = approved
        self.chainId = chainId
        self.accounts = accounts
    }
}

//MARK: - session approve
public protocol WCApproveSessionResponseType: Codable { }
public struct WCApproveSessionResponse: WCApproveSessionResponseType {
    public let approved: Bool
    public let chainId: Int
    public let accounts: [String]

    public let peerId: String?
    public let peerMeta: WCPeerMeta?

    public init(approved: Bool, chainId: Int, accounts: [String],
                peerId: String?, peerMeta: WCPeerMeta?) {
        self.approved = approved
        self.chainId = chainId
        self.accounts = accounts
        self.peerId = peerId
        self.peerMeta = peerMeta
    }
}
