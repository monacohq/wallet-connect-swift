// Copyright © 2017-2019 Trust Wallet.
//
// This file is part of Trust. The full Trust copyright notice, including
// terms governing use, modification, and redistribution, is contained in the
// file LICENSE at the root of the source code distribution tree.

import Foundation

/**
 Wallet address required coin types from extension's webSocket message.
 */
public enum WCSessionAddressRequiredCoinType: String, Codable {
    case eth = "eth"
    case cro = "cro"
    case tcro = "tcro"
}

public struct WCSessionRequestParam: Codable {
    public let peerId: String
    public let peerMeta: WCPeerMeta
    public let chainId: String?
    public let networkId: String?
    public let accountTypes: [WCSessionAddressRequiredCoinType]?

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        peerId = try values.decode(String.self, forKey: .peerId)
        peerMeta = try values.decode(WCPeerMeta.self, forKey: .peerMeta)
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
        networkId = try values.decodeIfPresent(String.self, forKey: .networkId)
        accountTypes = try values.decodeIfPresent([WCSessionAddressRequiredCoinType].self, forKey: .accountTypes)
    }
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

    public init(approved: Bool, chainId: Int?, accounts: [String]?,
                selectedWalletId: String? = nil,
                wallets: [WCSessionWalletInfo]? = nil) {
        self.approved = approved
        self.chainId = chainId
        self.accounts = accounts
        self.selectedWalletId = selectedWalletId
        self.wallets = wallets
    }

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
    /// wallet name
    public let name: String
    /// wallet id
    public let id: String
    /// wallet icon
    public let icon: String?
    /// wallet address dict, [symbol : address string]
    public let address: [String : String]

    public init(name: String, id: String,
                icon: String?, address: [String : String]) {
        self.name = name
        self.id = id
        self.icon = icon
        self.address = address
    }
}

public struct WCApproveSessionResponse: Codable {
    public let approved: Bool
    public let chainId: String
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
