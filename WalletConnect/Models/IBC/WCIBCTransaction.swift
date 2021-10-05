//
//  WCIBCTransaction.swift
//  ActiveLabel
//
//  Created by Hahn.Chen@crypto.com on 2021/9/28.
//

import Foundation
import UIKit
import SwiftUI

public struct WCIBCTransaction { }

extension WCIBCTransaction {
    public struct Body: Codable {
        public let memo: String
        public let timeoutHeight: String
        public let messages: [Message]
        public let extensionOptions: [String]
        public let nonCriticalExtensionOptions: [String]

        public struct Message: Codable {
            public let typeUrl: String
            public let value: Value

            public struct Value: Codable {
                public let sourcePort: String
                public let sourceChannel: String
                public let sender: String
                public let receiver: String
                public let timeoutTimestamp: String
                public let token: Token

                public struct Token: Codable {
                    public let denom: String
                    public let amount: String
                }
            }
        }
    }

    public struct AuthInfo: Codable {
        public let signerInfos: [SignerInfo]
        public let fee: Fee

        public struct SignerInfo: Codable {
            public let sequence: String
            public let modeInfo: ModeInfo

            public struct PublicKey: Codable {
                public let typeUrl: String
                public let value: String
            }

            public struct ModeInfo: Codable {
                public let single: Single

                public struct Single: Codable {
                    public let mode: SignerInfo.Mode
                }
            }

            /**
             * SIGN_MODE_UNSPECIFIED - SIGN_MODE_UNSPECIFIED specifies an unknown signing mode and will be
             * rejected
             *
             SIGN_MODE_UNSPECIFIED = 0,
             **
             * SIGN_MODE_DIRECT - SIGN_MODE_DIRECT specifies a signing mode which uses SignDoc and is
             * verified with raw bytes from Tx
             *
             SIGN_MODE_DIRECT = 1,
             **
             * SIGN_MODE_TEXTUAL - SIGN_MODE_TEXTUAL is a future signing mode that will verify some
             * human-readable textual representation on top of the binary representation
             * from SIGN_MODE_DIRECT
             *
             SIGN_MODE_TEXTUAL = 2,
             **
             * SIGN_MODE_LEGACY_AMINO_JSON - SIGN_MODE_LEGACY_AMINO_JSON is a backwards compatibility mode which uses
             * Amino JSON and will be removed in the future
             */
            public enum Mode: String, Codable {
                case SIGN_MODE_UNSPECIFIED
                case SIGN_MODE_DIRECT
                case SIGN_MODE_TEXTUAL
            }
        }

        public struct Fee: Codable {
            public typealias Amount = Body.Message.Value.Token

            public let gasLimit: String
            public let payer: String
            public let granter: String
            public let amount: [Amount]
        }

    }

    public struct SignDoc: Codable {
        public let chainId: String
        public let accountNumber: String
        public let body: Body
        public let authInfo: AuthInfo
    }

    public struct Signature: Codable {
        public let pub_key: Pub_key
        public let signature: String

        public init(pub_key: Pub_key, signature: String) {
            self.pub_key = pub_key
            self.signature = signature
        }

        public struct Pub_key: Codable {
            public let type: String
            public let value: String

            public init(type: String, value: String) {
                self.type = type
                self.value = value
            }
        }
    }
}

extension WCIBCTransaction {
    public struct RequestParam: Codable {
        public let signerAddress: String
        public let signDoc: SignDoc
    }

    public struct ResponseResult: Codable {
        public let signed: SignDoc
        public let signature: Signature

        public init(signed: SignDoc, signature: Signature) {
            self.signed = signed
            self.signature = signature
        }
    }
}
