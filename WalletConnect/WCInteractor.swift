// Copyright © 2017-2019 Trust Wallet.
//
// This file is part of Trust. The full Trust copyright notice, including
// terms governing use, modification, and redistribution, is contained in the
// file LICENSE at the root of the source code distribution tree.

import Foundation
import Starscream
import RxCocoa
import RxSwift

public typealias SessionRequestClosure = (_ id: Int64, _ peerParam: WCSessionRequestParam) -> Void
public typealias SessionKilledClosure = () -> Void
public typealias DisconnectClosure = (Error?) -> Void
public typealias CustomRequestClosure = (_ id: Int64, _ request: [String: Any]) -> Void
public typealias ErrorClosure = (Error) -> Void
public typealias ReceiveACKClosure = (_ message: WCInteractor.ACKMessage) -> Void

public enum WCInteractorState {
    case connected
    case connecting
    case paused
    case disconnected
}

open class WCInteractor {
    public let session: WCSession

    public let clientId: String
    public let clientMeta: WCPeerMeta
    public private(set) var addressRequiredCoinTypes = [WCSessionAddressRequiredCoinType]()
    public private(set) var chainType: String?

    public var eth: WCEthereumInteractor
    public var bnb: WCBinanceInteractor
    public var trust: WCTrustInteractor
    public var ibc: WCIBCInteractor

    // incoming event handlers
    public var onSessionRequest: SessionRequestClosure?
    public var onSessionKilled: SessionKilledClosure?
    public var onDisconnect: DisconnectClosure?
    public var onError: ErrorClosure?
    public var onCustomRequest: CustomRequestClosure?
    public var onReceiveACK: ReceiveACKClosure?

    private let socket: WebSocket
    private let maxReconnectCount: Int = 3
    private var handshakeId: Int64 = -1
    private weak var pingTimer: Timer?
    private weak var sessionTimer: Timer?
    private let sessionRequestTimeout: TimeInterval

    // subscription
    private var subscribedTopics = [String]()
    private let subscritionLock = NSLock()

    /// comes from dDapp or extension
    public var peerId: String? {
        didSet {
            if let peerID = peerId {
                /**
                 Why subscribe peerID?
                 ACK message is sent with peerID as topic
                 */
                subscribe(topic: peerID)
            }
        }
    }
    public var peerMeta: WCPeerMeta?

    // Rx
    private var stateRelay: BehaviorRelay<WCInteractorState>
    private let disposeBag = DisposeBag()

    public var state: WCInteractorState {
        return stateRelay.value
    }

    public init(session: WCSession, meta: WCPeerMeta,
                uuid: UUID, sessionRequestTimeout: TimeInterval = 20,
                addressRequiredCoinTypes: [WCSessionAddressRequiredCoinType]) {
        self.session = session
        self.clientId = uuid.description.lowercased()
        self.clientMeta = meta
        self.sessionRequestTimeout = sessionRequestTimeout
        self.addressRequiredCoinTypes = addressRequiredCoinTypes

        var request = URLRequest(url: session.bridge)
        request.timeoutInterval = sessionRequestTimeout
        let pinner = FoundationSecurity(allowSelfSigned: true)

        self.socket = WebSocket(request: request, certPinner: pinner)
        self.stateRelay = .init(value: .disconnected)

        self.eth = WCEthereumInteractor()
        self.bnb = WCBinanceInteractor()
        self.trust = WCTrustInteractor()
        self.ibc = WCIBCInteractor()

        socket.delegate = self

        WCLog("interactor init session.topic:\(session.topic) clientId:\(clientId)")
    }

    deinit {
        disconnect()
    }

    open func connect() -> Completable {
        let bag = disposeBag

        return Completable.create { [weak self] completable in
            if self?.stateRelay.value == .connected {
                completable(.completed)
            }
            
            self?.socket.connect()
            self?.stateRelay.accept(.connecting)

            let timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
                completable(.error(WCError.sessionRequestTimeout))
            }

            self?.stateRelay.subscribe(onNext: { state in
                if state == .connected {
                    completable(.completed)
                    timer.invalidate()
                }
            }).disposed(by: bag)

            return Disposables.create()
        }
    }

    open func pause() {
        stateRelay.accept(.paused)
        socket.disconnect(closeCode: CloseCode.goingAway.rawValue)
    }

    open func resume() {
        socket.connect()
        stateRelay.accept(.connecting)
    }

    open func disconnect() {
        stopTimers()

        socket.disconnect()
        stateRelay.accept(.disconnected)

        handshakeId = -1
    }

    open func approveSession(accounts: [String],
                             chainId: String,
                             selectedWalletId: String? = nil,
                             wallets: [WCSessionWalletInfo]? = nil) -> Completable {
        guard handshakeId > 0 else {
            return Completable.error(WCError.sessionInvalid)
        }
        let result = WCApproveSessionResponse(
            approved: true,
            chainId: chainId,
            accounts: accounts,
            peerId: clientId,
            peerMeta: clientMeta,
            chainType: chainType,
            selectedWalletId: selectedWalletId,
            wallets: wallets
        )
        let response = JSONRPCResponse(id: handshakeId, result: result)
        return encryptAndSend(data: response.encoded)
    }

    open func rejectSession(_ message: String = "Session Rejected") -> Completable {
        guard handshakeId > 0 else {
            return Completable.error(WCError.sessionInvalid)
        }
        let response = JSONRPCErrorResponse(id: handshakeId, error: JSONRPCError(code: -32000, message: message))
        return encryptAndSend(data: response.encoded)
    }

    @discardableResult
    open func killSession(method: WCEvent) -> Completable {
        let result = WCSessionUpdateParam(approved: false, chainId: nil, accounts: nil)
        let response = JSONRPCRequest(id: generateId(), method: method.rawValue, params: [result])
        let bag = disposeBag

        return Completable.create { [weak self] completable in
            self?.encryptAndSend(data: response.encoded).subscribe(
                onCompleted: {
                    self?.onSessionKilled?()
                    self?.disconnect()
                    completable(.completed)
                },
                onError: { error in
                    completable(.error(error))
                })
                .disposed(by: bag)

            return Disposables.create()
        }
    }

    @discardableResult
    open func updateSession(chainId: String, accounts: [String],
                            method: WCEvent,
                            selectedWalletId: String? = nil,
                            wallets: [WCSessionWalletInfo]? = nil) -> Completable {
        let result = WCSessionUpdateParam(approved: true,
                                          chainId: chainId,
                                          accounts: accounts,
                                          chainType: chainType,
                                          selectedWalletId: selectedWalletId,
                                          wallets: wallets)
        let response = JSONRPCRequest(id: generateId(), method: method.rawValue, params: [result])
        return encryptAndSend(data: response.encoded)
    }

//    open func approveBnbOrder(id: Int64, signed: WCBinanceOrderSignature) -> Promise<WCBinanceTxConfirmParam> {
//        let result = signed.encodedString
//        return approveRequest(id: id, result: result)
//            .then { _ -> Promise<WCBinanceTxConfirmParam> in
//                return Promise { [weak self] seal in
//                    self?.bnb.confirmResolvers[id] = seal
//                }
//            }
//    }

    open func approveRequest<T: Codable>(id: Int64, result: T) -> Completable {
        let response = JSONRPCResponse(id: id, result: result)
        return encryptAndSend(data: response.encoded)
    }

    open func rejectRequest(id: Int64, message: String) -> Completable {
        let response = JSONRPCErrorResponse(id: id, error: JSONRPCError(code: -32000, message: message))
        return encryptAndSend(data: response.encoded)
    }

    open func approveIBCTransaction(id: Int64, signed: String) -> Completable {
        guard let jsonData = signed.data(using: .utf8) else {
            return Completable.error(WCError.unknown) // TODO: unknown maybe not good enough
        }
        let decoder = JSONDecoder()
        guard let signedRequestParam = try? decoder.decode(WCIBCTransaction.RequestParam.self, from: jsonData), let signature = signedRequestParam.signDoc.signature else {
            return Completable.error(WCError.unknown) // TODO: unknown maybe not good enough
        }
        let response = JSONRPCResponse(id: id, result: signature.signature)
        return encryptAndSend(data: response.encoded)
    }
}

// MARK: internal funcs
extension WCInteractor {
    private func subscribe(topic: String) {
        subscritionLock.lock()
        guard !subscribedTopics.contains(topic) else {
            WCLog("\(topic) already subscribed")
            subscritionLock.unlock()
            return
        }
        subscritionLock.unlock()

        let message = WCSocketMessage(topic: topic, type: .sub, payload: "", timestamp: nil)
        let data = try! JSONEncoder().encode(message)
        socket.write(data: data)
        WCLog("==> subscribe: \(String(data: data, encoding: .utf8)!)")

        subscritionLock.lock()
        subscribedTopics.append(topic)
        subscritionLock.unlock()
    }

    private func encryptAndSend(data: Data) -> Completable {
        WCLog("==> encrypt: \(String(data: data, encoding: .utf8)!) ")
        let encoder = JSONEncoder()
        let payload = try! WCEncryptor.encrypt(data: data, with: session.key)
        let payloadString = encoder.encodeAsUTF8(payload)
        let message = WCSocketMessage(topic: peerId ?? session.topic, type: .pub, payload: payloadString, timestamp: nil)
        let data = message.encoded

        return Completable.create { [weak self] completable in
            let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                completable(.error(WCError.sessionRequestTimeout))
            }

            self?.socket.write(data: data) {
                WCLog("==> sent \(String(data: data, encoding: .utf8)!) ")
                timer.invalidate()
                completable(.completed)
            }

            return Disposables.create()
        }
    }

    private func handleEvent(_ event: WCEvent, topic: String, decrypted: Data) throws {
        switch event {
        case .sessionRequest, .dc_sessionRequest:
            // topic == session.topic
            let request: JSONRPCRequest<[WCSessionRequestParam]> = try event.decode(decrypted)
            guard let params = request.params.first else { throw WCError.badJSONRPCRequest }
            handshakeId = request.id
            peerId = params.peerId
            peerMeta = params.peerMeta
            chainType = params.chainType
            addressRequiredCoinTypes = params.accountTypes ?? []
            sessionTimer?.invalidate()
            onSessionRequest?(request.id, params)
        case .sessionUpdate, .dc_sessionUpdate:
            // topic == clientId
            let request: JSONRPCRequest<[WCSessionUpdateParam]> = try event.decode(decrypted)
            guard let param = request.params.first else { throw WCError.badJSONRPCRequest }
            if param.approved == false {
                disconnect()
                self.onSessionKilled?()
            }
        case .cosmos_sendTransaction:
            let request: JSONRPCRequest<[WCIBCTransaction.RequestParam]> = try event.decode(decrypted)
            guard let param = request.params.first else { throw WCError.badJSONRPCRequest }
            let transaction = WCIBCTransaction(requestParam: param)
            ibc.onTransaction?(request.id, event, transaction, request.session)
        default:
            if WCEvent.eth.contains(event) {
                try eth.handleEvent(event, topic: topic, decrypted: decrypted)
            } else if WCEvent.bnb.contains(event) {
                try bnb.handleEvent(event, topic: topic, decrypted: decrypted)
            } else if WCEvent.trust.contains(event) {
                try trust.handleEvent(event, topic: topic, decrypted: decrypted)
            }
        }
    }

    private func checkExistingSession() {
        // check if it's an existing session
        if let existing = WCSessionStore.load(session.topic), existing.session == session {
            peerId = existing.peerId
            peerMeta = existing.peerMeta
            return
        }

        // we only setup timer for new sessions
        sessionTimer = Timer.scheduledTimer(withTimeInterval: sessionRequestTimeout, repeats: false) { [weak self] _ in
            self?.onSessionRequestTimeout()
        }
    }

    private func stopTimers() {
        pingTimer?.invalidate()
        sessionTimer?.invalidate()
    }

    private func onSessionRequestTimeout() {
        onDisconnect(error: WCError.sessionRequestTimeout)
    }
}

// MARK: WebSocket event handler
extension WCInteractor {
    private func onConnect() {
        checkExistingSession()

        subscribe(topic: session.topic)
        subscribe(topic: clientId)
    }

    private func onDisconnect(error: Error?) {
        stopTimers()
        onDisconnect?(error)
    }

    private func onReceiveMessage(text: String) {
        WCLog("<== receive: \(text)")
        guard let (topic, messageType, payload, timestamp) = WCEncryptionPayload.extract(text) else { return }
        switch messageType {
        case .ack:
            WCLog("<== receive: ACK")
            onReceiveACK?(.rawMessage(topic: topic, payload: payload, timestamp: timestamp))
        default:
            guard let payload = payload else { return }
            do {
                let decrypted = try WCEncryptor.decrypt(payload: payload, with: session.key)
                guard let json = try JSONSerialization.jsonObject(with: decrypted, options: [])
                    as? [String: Any] else {
                    throw WCError.badJSONRPCRequest
                }
                WCLog("<== decrypted: \(String(data: decrypted, encoding: .utf8)!)")
                if let method = json["method"] as? String {
                    if let event = WCEvent(rawValue: method) {
                        try handleEvent(event, topic: topic, decrypted: decrypted)
                    } else if let id = json["id"] as? Int64 {
                        onCustomRequest?(id, json)
                    }
                }
            } catch let error {
                onError?(error)
                WCLog("==> onReceiveMessage error: \(error.localizedDescription)")
            }
        }
    }
}

extension WCInteractor {
    public enum ACKMessage {
        case plain
        case rawMessage(topic: String, payload: WCEncryptionPayload?,
                        timestamp: UInt64?)
    }
}

// MARK: - WebSocketDelegate
extension WCInteractor: WebSocketDelegate {
    public func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected(let headers):
            WCLog("<== websocketDidConnected:\n\(headers)")
            stateRelay.accept(.connected)
            onConnect()
        case .disconnected(let reason, let code):
            WCLog("<== websocketDidDisconnected:\n\(reason) with code: \(code)")

            if code == 4022 {
                let error = WCError.tooManyMessages(desc: reason)
                onDisconnect(error: error)
                stateRelay.accept(.disconnected)
                return
            }

            reconnect()
        case .text(let text):
            onReceiveMessage(text: text)
        case .binary(let data):
            WCLog("<== websocketDidReceiveData:\n\(data.toHexString())")
        case .pong:
            WCLog("<== pong")
        case .ping:
            WCLog("==> ping")
        case .error(let error):
            WCLog("<== websocketDidDisconnected:\nerror:\(error.debugDescription)")
            reconnect()
        case .viabilityChanged(let bool):
            WCLog("<== websocketViabilityChanged: \(bool)")
        case .reconnectSuggested(let shouldReconnect):
            if shouldReconnect {
                reconnect()
            }
            WCLog("<== websocketReconnectSuggested: \(shouldReconnect)")
        case .cancelled:
            // disconnection triggered by users
            WCLog("<== websocketDidCancelled")
            stateRelay.accept(.disconnected)
            onDisconnect(error: nil)
        }
    }

    private func reconnect() {
        guard state != .connecting && state != .connected else { return }

        let reconnectCount = self.maxReconnectCount
        let bag = self.disposeBag

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.connect().retry(reconnectCount)
                .subscribe(onCompleted: {
                    WCLog("<== websocketDidReconnected")
                }, onError: { [weak self] error in
                    self?.stateRelay.accept(.disconnected)
                    self?.onDisconnect(error: error)
                    WCLog("<== websocketFailedToReconnect:\nerror:\(error.localizedDescription)")
                }).disposed(by: bag)
        }
    }
}
