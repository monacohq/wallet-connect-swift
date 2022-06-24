// Copyright © 2017-2019 Trust Wallet.
//
// This file is part of Trust. The full Trust copyright notice, including
// terms governing use, modification, and redistribution, is contained in the
// file LICENSE at the root of the source code distribution tree.

import Foundation

public protocol WCEventType {
    var rawValue: String { get }
    func decode<T: Codable>(_ data: Data) throws -> JSONRPCRequest<T>
}

extension WCEventType {
    public func decode<T: Codable>(_ data: Data) throws -> JSONRPCRequest<T> {
        return try JSONDecoder().decode(JSONRPCRequest<T>.self, from: data)
    }
}
public enum WCEvent: String, WCEventType {
    case sessionRequest = "wc_sessionRequest"
    case sessionUpdate = "wc_sessionUpdate"

    case ethSign = "eth_sign"
    case ethPersonalSign = "personal_sign"

    case ethSignTypeData = "eth_signTypedData"
    case ethSignTypeData_v2 = "eth_signTypedData_v2"
    case ethSignTypeData_v3 = "eth_signTypedData_v3"
    case ethSignTypeData_v4 = "eth_signTypedData_v4"

    case ethSignTransaction = "eth_signTransaction"
    case ethSendTransaction = "eth_sendTransaction"

    case bnbSign = "bnb_sign"
    case bnbTransactionConfirm = "bnb_tx_confirmation"
    case trustSignTransacation = "trust_signTransaction"
    case getAccounts = "get_accounts"

//    /// extension phase 3 update
//    case cosmos_sendTransaction
//
//    case dc_instantRequest
//    case dc_sessionRequest
//    case dc_sessionUpdate
//    case dc_killSession
}

extension WCEvent {

    static let eth = Set<WCEvent>([.ethSign, .ethPersonalSign, .ethSignTypeData, .ethSignTypeData_v2, .ethSignTypeData_v3, .ethSignTypeData_v4, .ethSignTransaction, .ethSendTransaction])
    static let bnb = Set<WCEvent>([.bnbSign, .bnbTransactionConfirm])
    static let trust = Set<WCEvent>([.trustSignTransacation, .getAccounts])
//  static let dc = Set<WCEvent>([.dc_instantRequest, .dc_sessionRequest,
//                                         .dc_sessionUpdate, .dc_killSession])
}
