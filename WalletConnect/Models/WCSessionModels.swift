// Copyright © 2017-2019 Trust Wallet.
//
// This file is part of Trust. The full Trust copyright notice, including
// terms governing use, modification, and redistribution, is contained in the
// file LICENSE at the root of the source code distribution tree.

import Foundation

public struct WCSessionRequestParam: Codable {
    public let peerId: String
    public let peerMeta: WCPeerMeta
    public let chainId: Int?
}

public struct WCSessionUpdateParam: Codable {
    public let approved: Bool
    public let chainId: Int?
    public let accounts: [String]?

    /**
     Current selected wallet id.

     Not nil when response to our __Crypto.com extension__
     */
    public let selectedWalletId: String?
    /**
     All wallets infos

     Not nil when response to our __Crypto.com extension__
     */
    public let wallets: [WCSessionWalletInfo]?

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(approved, forKey: .approved)
        try container.encode(chainId, forKey: .chainId)
        try container.encode(accounts, forKey: .accounts)
        try container.encode(selectedWalletId, forKey: .selectedWalletId)
        try container.encode(wallets, forKey: .wallets)
    }
}

public struct WCSessionWalletInfo: Codable {
    public let name: String
    public let id: String
    public let icon: String?
    public let address: [String : String]
}

public struct WCApproveSessionResponse: Codable {
    public let approved: Bool
    public let chainId: Int
    public let accounts: [String]

    public let peerId: String?
    public let peerMeta: WCPeerMeta?

    /**
     Current selected wallet id.

     Not nil when response to our __Crypto.com extension__
     */
    public let selectedWalletId: String?
    /**
     All wallets infos

     Not nil when response to our __Crypto.com extension__
     */
    public let wallets: [WCSessionWalletInfo]?
}
