// Copyright © 2017-2019 Trust Wallet.
//
// This file is part of Trust. The full Trust copyright notice, including
// terms governing use, modification, and redistribution, is contained in the
// file LICENSE at the root of the source code distribution tree.

import Foundation
import CryptoSwift

public struct WCSession: Codable, Equatable {
    public let decodedString: String
    public let topic: String
    public let version: String
    public let bridge: URL
    public let key: Data
    public let numericalVersion: Double
    public let componentDicts: [String : String]

    public static func from(string: String) -> WCSession? {
        guard let decodedString = WCSession.urlDecodeIfNeed(string: string) else {
            return nil
        }

        let subStrings = decodedString.split(separator: ":")

        var urlString = ""

        subStrings.enumerated().forEach { index, subString in
            urlString += "\(subString)"
            if index == 0 {
                urlString += "://"
            }
        }

        guard let url = URL(string: urlString),
              let topic = url.user,
              let version = url.host,
              let components = NSURLComponents(url: url, resolvingAgainstBaseURL: false) else {
                  return nil
              }

        var dicts = [String: String]()
        for query in components.queryItems ?? [] {
            if let value = query.value {
                dicts[query.name] = value
            }
        }
        guard let bridge = dicts["bridge"],
              let bridgeUrl = URL(string: bridge),
              let key = dicts["key"] else {
                  return nil
              }

        return WCSession(decodedString: decodedString, topic: topic,
                         version: version, bridge: bridgeUrl,
                         key: Data(hex: key),
                         numericalVersion: Double(version) ?? 1.0,
                         componentDicts: dicts)
    }

    // may extract this to external implementation
    private static func urlDecodeIfNeed(string: String) -> String? {
        if string.hasPrefix("wc:") || string.hasPrefix("CWE:") {
            return string
        } else {
            return string.removingPercentEncoding
        }
    }
}
