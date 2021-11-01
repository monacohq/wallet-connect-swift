// Copyright © 2017-2019 Trust Wallet.
//
// This file is part of Trust. The full Trust copyright notice, including
// terms governing use, modification, and redistribution, is contained in the
// file LICENSE at the root of the source code distribution tree.

import Foundation

public protocol WalletConnectLogger {
    func debug(_ message: String,
               file: String,
               function: String,
               line: Int)

    func info(_ message: String,
              file: String,
              function: String,
              line: Int)

    func error(_ message: String,
               file: String,
               function: String,
               line: Int)
}

public class WCLogger {
    public static let shared = WCLogger()
    private(set) var logger: WalletConnectLogger = WCInternalLogger()

    public static func register(logger: WalletConnectLogger) {
        shared.logger = logger
    }

    public static func debug(_ message: String,
                             _ file: String = #file,
                             _ function: String = #function,
                             line: Int = #line) {

        shared.logger.debug("[WCLOG] " + message,
                            file: file,
                            function: function,
                            line: line)
    }

    public static func info(_ message: String,
                            _ file: String = #file,
                            _ function: String = #function,
                            line: Int = #line) {

        shared.logger.info("[WCLOG] " + message,
                           file: file,
                           function: function,
                           line: line)
    }

    public static func error(_ message: String,
                             _ file: String = #file,
                             _ function: String = #function,
                             line: Int = #line) {

        shared.logger.error("[WCLOG] " + message,
                            file: file,
                            function: function,
                            line: line)
    }
}

class WCInternalLogger: WalletConnectLogger {

    func debug(_ message: String,
               file: String,
               function: String,
               line: Int) {
        WCLog("[WCLOG] debug " + message)
    }

    func info(_ message: String,
              file: String,
              function: String,
              line: Int) {
        WCLog("[WCLOG] info " + message)
    }

    func error(_ message: String,
               file: String,
               function: String,
               line: Int) {
        WCLog("[WCLOG] error " + message)
    }

    func WCLog(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        #if DEBUG
        items.forEach {
            Swift.print("\($0)", separator: separator, terminator: terminator)
        }
        #endif
    }
}
