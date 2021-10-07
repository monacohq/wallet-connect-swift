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
    public let chainType: String?
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
        chainType = try values.decodeIfPresent(String.self, forKey: .chainType)
        accountTypes = try values.decodeIfPresent([WCSessionAddressRequiredCoinType].self, forKey: .accountTypes)
    }
}

public struct WCSessionUpdateParam: Codable {
    public let approved: Bool
    public let chainId: String?
    public let accounts: [String]?

    /**
     'eth' or 'cosmos'
     */
    public let chainType: String?

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

    public init(approved: Bool, chainId: String?, accounts: [String]?,
                chainType: String? = nil,
                selectedWalletId: String? = nil,
                wallets: [WCSessionWalletInfo]? = nil) {
        self.approved = approved
        self.chainId = chainId
        self.accounts = accounts
        self.chainType = chainType
        self.selectedWalletId = selectedWalletId
        self.wallets = wallets
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(approved, forKey: .approved)
        try container.encode(chainId, forKey: .chainId)
        try container.encode(accounts, forKey: .accounts)
        try container.encodeIfPresent(chainType, forKey: .chainType)
        try container.encodeIfPresent(selectedWalletId, forKey: .selectedWalletId)
        try container.encodeIfPresent(wallets, forKey: .wallets)
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
    public let addresses: [String : WalletAddress]

    public init(name: String, id: String,
                icon: String?, addresses: [String : WalletAddress]) {
        self.name = name
        self.id = id
        self.icon = icon
        self.addresses = addresses
    }

    public struct WalletAddress: Codable {
        let address: String
        let algo: String?
        let pubkey: String?

        public init(address: String, pubkey: String?) {
            // in case of eth address, algo and pubkey do not exist
            self.algo = pubkey != nil ? "secp256k1" : nil
            self.address = address
            self.pubkey = pubkey
        }
    }
}

public struct WCApproveSessionResponse: Codable {
    public let approved: Bool
    public let chainId: String
    public let accounts: [String]

    public let peerId: String?
    public let peerMeta: WCPeerMeta?

    /**
     'eth' or 'cosmos'
     */
    public let chainType: String?

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

    public init(approved: Bool, chainId: String, accounts: [String],
                peerId: String?, peerMeta: WCPeerMeta?,
                chainType: String? = nil,
                selectedWalletId: String? = nil,
                wallets: [WCSessionWalletInfo]? = nil) {
        self.approved = approved
        self.chainId = chainId
        self.accounts = accounts
        self.peerId = peerId
        self.peerMeta = peerMeta
        self.chainType = chainType
        self.selectedWalletId = selectedWalletId
        self.wallets = wallets
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(approved, forKey: .approved)
        try container.encode(chainId, forKey: .chainId)
        try container.encode(accounts, forKey: .accounts)
        try container.encode(peerId, forKey: .peerId)
        try container.encode(peerMeta, forKey: .peerMeta)
        try container.encodeIfPresent(chainType, forKey: .chainType)
        try container.encodeIfPresent(selectedWalletId, forKey: .selectedWalletId)
        try container.encodeIfPresent(wallets, forKey: .wallets)
    }
}
