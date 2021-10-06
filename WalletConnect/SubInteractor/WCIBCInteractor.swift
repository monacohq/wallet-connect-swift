//
//  WCIBCInteractor.swift
//  WalletConnect
//
//  Created by Hahn.Chen@crypto.com on 2021/10/6.
//

import Foundation

public typealias IBCTransactionClosure = EthTransactionClosure

public struct WCIBCInteractor {
    public var onTransaction: IBCTransactionClosure?
}
