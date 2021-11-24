// Copyright © 2017-2019 Trust Wallet.
//
// This file is part of Trust. The full Trust copyright notice, including
// terms governing use, modification, and redistribution, is contained in the
// file LICENSE at the root of the source code distribution tree.

import Foundation
import Starscream
import PromiseKit

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

public protocol WCInteractorDelegate: class {
    func handleEvent(_ event: WCEvent, topic: String,
                     decrypted: Data, timestamp: UInt64?) throws
}

open class WCInteractor {
    public let session: WCSession

    public private(set) var state: WCInteractorState

    public let clientId: String
    public let clientMeta: WCPeerMeta
    public private(set) var chainType: String?
    weak var delegate: WCInteractorDelegate?

    // incoming event handlers
    public var onSessionRequest: SessionRequestClosure?
    public var onSessionKilled: SessionKilledClosure?
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

        socket.onConnect = { [weak self] in self?.onConnect() }
        socket.onDisconnect = { [weak self] error in self?.onDisconnect(error: error) }
        socket.onText = { [weak self] text in self?.onReceiveMessage(text: text) }
        socket.onPong = { _ in WCLogger.info("<== pong") }
        socket.onData = { data in WCLogger.info("<== websocketDidReceiveData: \(data.toHexString())") }

        WCLogger.info("interactor init session.topic:\(session.topic) clientId:\(clientId)")
    }

    deinit {
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
    open func approveSession<T: Codable>(result: T) -> Promise<Void> {
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
    open func killSession(method: WCEvent) -> Promise<Void> {
        let result = WCSessionUpdateParam(approved: false, chainId: nil, accounts: nil)
        let response = JSONRPCRequest(id: generateId(), method: method.rawValue, params: [result])
        return encryptAndSend(data: response.encoded)
            .map { [weak self] in
                self?.onSessionKilled?()
                self?.disconnect()
            }
    }

    @discardableResult
    open func updateSession<T: Codable>(request: T) -> Promise<Void> {
        return encryptAndSend(data: request.encoded)
    }

    // MARK: - request operations
    @discardableResult
    open func approveRequest<T: Codable>(id: Int64, result: T) -> Promise<Void> {
        let response = JSONRPCResponse(id: id, result: result)
        return encryptAndSend(data: response.encoded)
    }

    @discardableResult
    open func rejectRequest(id: Int64, message: String) -> Promise<Void> {
        let response = JSONRPCErrorResponse(id: id, error: JSONRPCError(code: -32000, message: message))
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

    public func setupSessionRequest(request: JSONRPCRequest<[WCSessionRequestParam]>) throws {
        guard let params = request.params.first else { throw WCError.badJSONRPCRequest }
        handshakeId = request.id
        peerId = params.peerId
        peerMeta = params.peerMeta
        chainType = params.chainType
        sessionTimer?.invalidate()
        onSessionRequest?(request.id, params)
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

        connectResolver?.fulfill(true)
        connectResolver = nil

        state = .connected
    }

    private func onDisconnect(error: Error?) {
        WCLogger.info("<== websocketDidDisconnect, error: \(error.debugDescription)")

        stopTimers()

        if let error = error {
            connectResolver?.reject(error)
        } else {
            connectResolver?.fulfill(false)
        }

        connectResolver = nil
        onDisconnect?(error)

        state = .disconnected
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
                        try delegate?.handleEvent(event, topic: topic,
                                                  decrypted: decrypted,
                                                  timestamp: timestamp)
                    } else if let id = json["id"] as? Int64 {
                        onCustomRequest?(id, json)
                    }
                }
            } catch let error {
                onError?(error)
                WCLogger.info("==> onReceiveMessage error: \(error.localizedDescription)")
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
