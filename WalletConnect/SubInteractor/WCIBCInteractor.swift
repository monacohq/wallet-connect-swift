//
//  WCIBCInteractor.swift
//  WalletConnect
//
//  Created by Hahn.Chen@crypto.com on 2021/10/6.
//

import Foundation

public typealias IBCTransactionClosure = (_ id: Int64, _ event: WCEvent,
                                          _ transaction: WCIBCTransaction,
                                          _ session: JSONRPCSession?) -> Void

public struct WCIBCInteractor {
    public var onTransaction: IBCTransactionClosure?
}
