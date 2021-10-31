// Copyright © 2017-2019 Trust Wallet.
//
// This file is part of Trust. The full Trust copyright notice, including
// terms governing use, modification, and redistribution, is contained in the
// file LICENSE at the root of the source code distribution tree.

import Foundation
import CryptoSwift

public struct WCSession: Codable, Equatable {
    public enum Source: String, Codable {
        case unknown
        case wc
        case cwe

        public var prefix: String {
            switch self {
            case .unknown:
                return ""
            case .wc:
                return "wc"
            case .cwe:
                return "CWE"
            }
        }
    }
    public static let legacySessionVersion = 1.0
    public let topic: String
    public let version: String
    public let bridge: URL
    public let key: Data
    public let numericalVersion: Double
    public let source: Source
    public let isExtension: Bool

    public static func from(string: String) -> WCSession? {
        var source = Source.unknown

        guard let decodedString = WCSession.urlDecodeIfNeed(string: string) else {
            return nil
        }

        if decodedString.hasPrefix("wc:") {
            source = .wc
        } else if decodedString.hasPrefix("CWE:") {
            source = .cwe
        } else {
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

        return WCSession(topic: topic, version: version, bridge: bridgeUrl,
                         key: Data(hex: key),
                         numericalVersion: Double(version) ?? 1.0,
                         source: source,
                         isExtension: dicts["role"] == "extension")
    }

    private static func urlDecodeIfNeed(string: String) -> String? {
        if string.hasPrefix("wc:") || string.hasPrefix("CWE:") {
            return string
        } else {
            return string.removingPercentEncoding
        }
    }
}
