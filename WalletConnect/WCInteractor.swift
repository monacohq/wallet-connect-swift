// Copyright © 2017-2019 Trust Wallet.
//
// This file is part of Trust. The full Trust copyright notice, including
// terms governing use, modification, and redistribution, is contained in the
// file LICENSE at the root of the source code distribution tree.

import Foundation
import Starscream
import PromiseKit

public typealias SessionKilledClosure = () -> Void
public typealias ConnectedClosure = () -> Void
public typealias DisconnectClosure = (Error?) -> Void
public typealias CustomRequestClosure = (_ id: Int64, _ request: [String: Any],
                                         _ timestamp: UInt64?) -> Void
public typealias ErrorClosure = (Error) -> Void
public typealias ReceiveACKClosure = (_ message: WCInteractor.ACKMessage) -> Void

public enum WCInteractorState {
    case connected
    case connecting
    case paused
    case disconnected
}

public protocol WCInteractorDelegate: class {
    func onSessionRequest(param: WCSessionRequestParamType)
}

open class WCInteractor {
    public let session: WCSession

    public private(set) var state: WCInteractorState

    public let clientId: String
    public let clientMeta: WCPeerMeta
    public private(set) var chainType: String?
    public weak var delegate: WCInteractorDelegate?

    public var eth: WCEthereumInteractor
    public var bnb: WCBinanceInteractor
    public var trust: WCTrustInteractor

    // incoming event handlers
    public var onSessionKilled: SessionKilledClosure?
    public var onConnected: ConnectedClosure?
    public var onDisconnect: DisconnectClosure?
    public var onError: ErrorClosure?
    public var onCustomRequest: CustomRequestClosure?
    public var onReceiveACK: ReceiveACKClosure?

    // outgoing promise resolvers
    private var connectResolver: Resolver<Bool>?

    private let socket: WebSocket
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

    public init(session: WCSession, meta: WCPeerMeta, uuid: UUID, sessionRequestTimeout: TimeInterval = 20) {
        self.session = session
        self.clientId = uuid.description.lowercased()
        self.clientMeta = meta
        self.sessionRequestTimeout = sessionRequestTimeout
        self.state = .disconnected

        var request = URLRequest(url: session.bridge)
        request.timeoutInterval = sessionRequestTimeout
        self.socket = WebSocket(request: request)

        self.eth = WCEthereumInteractor()
        self.bnb = WCBinanceInteractor()
        self.trust = WCTrustInteractor()

        socket.onConnect = { [weak self] in self?.onConnect() }
        socket.onDisconnect = { [weak self] error in self?.onDisconnect(error: error) }
        socket.onText = { [weak self] text in self?.onReceiveMessage(text: text) }
        socket.onPong = { _ in WCLogger.info("<== pong") }
        socket.onData = { data in WCLogger.info("<== websocketDidReceiveData: \(data.toHexString())") }

        WCLogger.info("interactor init session.topic:\(session.topic) clientId:\(clientId)")
    }

    deinit {
        WCLogger.info("🔥 deinit session.topic:\(session.topic) clientId:\(clientId)")
        disconnect()
    }

    // MARK: - basic abilities
    open func connect() -> Promise<Bool> {
        if socket.isConnected {
            return Promise.value(true)
        }
        socket.connect()
        state = .connecting
        return Promise<Bool> { [weak self] seal in
            self?.connectResolver = seal
        }
    }

    open func pause() {
        state = .paused
        socket.disconnect(forceTimeout: nil, closeCode: CloseCode.goingAway.rawValue)
    }

    open func resume() {
        socket.connect()
        state = .connecting
    }

    open func disconnect() {
        stopTimers()

        socket.disconnect()
        state = .disconnected

        connectResolver = nil
        handshakeId = -1
    }

    // MARK: - session operations
    @discardableResult
    open func approveSession<T: WCApproveSessionResponseType>(result: T) -> Promise<Void> {
        guard handshakeId > 0 else {
            return Promise(error: WCError.sessionInvalid)
        }
        let response = JSONRPCResponse(id: handshakeId, result: result)
        return encryptAndSend(data: response.encoded)
    }

    @discardableResult
    open func rejectSession(_ message: String = "Session Rejected") -> Promise<Void> {
        guard handshakeId > 0 else {
            return Promise(error: WCError.sessionInvalid)
        }
        let response = JSONRPCErrorResponse(id: handshakeId, error: JSONRPCError(code: -32000, message: message))
        return encryptAndSend(data: response.encoded)
    }

    @discardableResult
    open func killSession<T: WCSessionUpdateParamType>(method: WCEventType, param: T) -> Promise<Void> {
        let response = JSONRPCRequest(id: generateId(), method: method.rawValue, params: [param])
        return encryptAndSend(data: response.encoded)
            .map { [weak self] in
                self?.onSessionKilled?()
                self?.disconnect()
            }
    }

    @discardableResult
    open func updateSession<T: WCSessionUpdateParamType>(method: WCEventType, param: T) -> Promise<Void> {
        let request = JSONRPCRequest(id: generateId(), method: method.rawValue,
                                     params: [param])
        return encryptAndSend(data: request.encoded)
    }

    // MARK: - request operations
    @discardableResult
    open func approveRequest<T: Codable>(id: Int64, result: T) -> Promise<Void> {
        let response = JSONRPCResponse(id: id, result: result)
        return encryptAndSend(data: response.encoded)
    }

    open func sendRequest<T: Codable>(id: Int64, method: String, request: T) -> Promise<Void> {
        let request = JSONRPCRequest(id: id, method: method, params: request)
        return encryptAndSend(data: request.encoded)
    }

    @discardableResult
    open func rejectRequest(id: Int64, message: String) -> Promise<Void> {
        // due to https://eips.ethereum.org/EIPS/eip-1193
        // 4001    User Rejected Request    The user rejected the request.
        // reject transaction should send 4001
        let response = JSONRPCErrorResponse(id: id, error: JSONRPCError(code: 4001, message: message))
        return encryptAndSend(data: response.encoded)
    }
}

// MARK: internal funcs
extension WCInteractor {
    private func subscribe(topic: String) {
        subscritionLock.lock()
        guard !subscribedTopics.contains(topic) else {
            WCLogger.info("\(topic) already subscribed")
            subscritionLock.unlock()
            return
        }
        subscritionLock.unlock()

        let message = WCSocketMessage(topic: topic, type: .sub, payload: "", timestamp: nil)
        let data = try! JSONEncoder().encode(message)
        socket.write(data: data)
        WCLogger.info("==> subscribe: \(String(data: data, encoding: .utf8)!)")

        subscritionLock.lock()
        subscribedTopics.append(topic)
        subscritionLock.unlock()
    }

    private func resetSubscriptions() {
        subscritionLock.lock(); defer { subscritionLock.unlock() }
        subscribedTopics.removeAll()
    }

    public func setupRequestingSession(id: Int64, peerId: String?,
                                       peerMeta: WCPeerMeta, chainType: String?) {
        self.handshakeId = id
        self.peerId = peerId
        self.peerMeta = peerMeta
        self.chainType = chainType
        sessionTimer?.invalidate()
    }

    private func encryptAndSend(data: Data) -> Promise<Void> {
        WCLogger.info("==> encrypt: \(String(data: data, encoding: .utf8)!) ")
        let encoder = JSONEncoder()
        let payload = try! WCEncryptor.encrypt(data: data, with: session.key)
        let payloadString = encoder.encodeAsUTF8(payload)
        let message = WCSocketMessage(topic: peerId ?? session.topic, type: .pub, payload: payloadString, timestamp: nil)
        let data = message.encoded
        return Promise { seal in
            socket.write(data: data) {
                WCLogger.info("==> sent \(String(data: data, encoding: .utf8)!) ")
                seal.fulfill(())
            }
        }
    }

    private func setupPingTimer() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak socket] _ in
            WCLogger.info("==> ping")
            socket?.write(ping: Data())
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
        WCLogger.info("<== websocketDidConnect")

        setupPingTimer()
        checkExistingSession()

        subscribe(topic: session.topic)
        subscribe(topic: clientId)

        state = .connected

        connectResolver?.fulfill(true)
        connectResolver = nil
        onConnected?()
    }

    private func onDisconnect(error: Error?) {
        WCLogger.info("<== websocketDidDisconnect, error: \(error.debugDescription)")

        stopTimers()

        resetSubscriptions()

        state = .disconnected

        if let error = error {
            connectResolver?.reject(error)
        } else {
            connectResolver?.fulfill(false)
        }

        connectResolver = nil
        onDisconnect?(error)
    }

    private func onReceiveMessage(text: String) {
        WCLogger.info("<== receive: \(text)")
        // handle ping in text format :(
        if text == "ping" { return socket.write(pong: Data()) }
        guard let (topic, messageType, payload, timestamp) = WCEncryptionPayload.extract(text) else { return }
        switch messageType {
        case .ack:
            WCLogger.info("<== receive: ACK")
            onReceiveACK?(.rawMessage(topic: topic, payload: payload, timestamp: timestamp))
        default:
            guard let payload = payload else { return }
            do {
                let decrypted = try WCEncryptor.decrypt(payload: payload, with: session.key)
                guard let json = try JSONSerialization.jsonObject(with: decrypted, options: [])
                    as? [String: Any] else {
                    throw WCError.badJSONRPCRequest
                }
                WCLogger.info("<== decrypted: \(String(data: decrypted, encoding: .utf8)!)")
                if let method = json["method"] as? String {
                    if let event = WCEvent(rawValue: method) {
                        try handleEvent(event, topic: topic,
                                        decrypted: decrypted,
                                        timestamp: timestamp)
                    } else if let id = json["id"] as? Int64 {
                        onCustomRequest?(id, json, timestamp)
                    }
                }
            } catch let error {
                onError?(error)
                WCLogger.info("==> onReceiveMessage error: \(error.localizedDescription)")
            }
        }
    }

    private func handleEvent(_ event: WCEvent, topic: String,
                             decrypted: Data, timestamp: UInt64?) throws {
        switch event {
        case .sessionRequest:
            // topic == session.topic
            let request: JSONRPCRequest<[WCSessionRequestParam]> = try event.decode(decrypted)
            guard let param = request.params.first else { throw WCError.badJSONRPCRequest }
            setupRequestingSession(id: request.id,
                                   peerId: param.peerId,
                                   peerMeta: param.peerMeta,
                                   chainType: nil)
            delegate?.onSessionRequest(param: param)
        case .sessionUpdate:
            // topic == clientId
            let request: JSONRPCRequest<[WCSessionUpdateParam]> = try event.decode(decrypted)
            guard let param = request.params.first else { throw WCError.badJSONRPCRequest }
            if param.approved == false {
                disconnect()
                onSessionKilled?()
            }
        default:
            if WCEvent.eth.contains(event) {
                try eth.handleEvent(event, topic: topic,
                                    decrypted: decrypted, timestamp: timestamp)
            } else if WCEvent.bnb.contains(event) {
                try bnb.handleEvent(event, topic: topic, decrypted: decrypted)
            } else if WCEvent.trust.contains(event) {
                try trust.handleEvent(event, topic: topic, decrypted: decrypted)
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
