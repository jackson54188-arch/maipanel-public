import Foundation
import Network

/// TCP server the PC bridge dials. This demo only speaks the frames it needs:
/// it announces its slot and asks for the video stream on connect, answers
/// keep-alive pings and hands JPEG frames to `VideoSink`.
final class ShellServer {
    private let queue = DispatchQueue(label: "maipanel.shell.server")
    private var listener: NWListener?
    private var connection: NWConnection?
    private var keepAlive: DispatchSourceTimer?
    private var inbox: [UInt8] = []
    private var slot = 1
    private var deliveredVideo = false

    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onVideo: ((Data) -> Void)?
    /// Fires once per connection, when the first video frame arrives.
    var onVideoStarted: (() -> Void)?

    /// Restart on a new port; `stop()` runs first, so a slot switch never
    /// leaves the old listener bound.
    func start(port: UInt16, slot: Int) {
        stop()
        queue.async { [weak self] in
            guard let self else { return }
            self.slot = slot
            do {
                let tcp = NWProtocolTCP.Options()
                // Video frames are small and back to back; Nagle would stall
                // each one for a full round trip.
                tcp.noDelay = true
                let parameters = NWParameters(tls: nil, tcp: tcp)
                parameters.allowLocalEndpointReuse = true
                let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }
                listener.start(queue: self.queue)
                self.listener = listener
            } catch {
                NSLog("listener error: \(error)")
            }

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 1, repeating: 1)
            timer.setEventHandler { [weak self] in
                guard let self, let connection = self.connection else { return }
                self.send(encodeFrame(.ping, Data()), on: connection)
            }
            timer.resume()
            self.keepAlive = timer
        }
    }

    /// Close the listener so the app can come back on the other slot's port.
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.keepAlive?.cancel()
            self.keepAlive = nil
            self.listener?.cancel()
            self.listener = nil
            self.connection?.cancel()
            self.connection = nil
            self.inbox.removeAll()
        }
    }

    private func accept(_ connection: NWConnection) {
        self.connection?.cancel()
        self.connection = connection
        inbox.removeAll()
        deliveredVideo = false
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async { self.onConnected?() }
                self.send(encodeSlotControl(self.slot), on: connection)
                self.send(encodeVideoControl(true), on: connection)
                self.send(encodeFrame(.ping, Data()), on: connection)
                self.receive(on: connection)
            case .failed, .cancelled:
                if self.connection === connection {
                    self.connection = nil
                    DispatchQueue.main.async { self.onDisconnected?() }
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.handleIncoming(data)
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.receive(on: connection)
        }
    }

    /// TCP may split or coalesce frames, so keep a byte buffer and cut frames
    /// by their length field instead of assuming one callback equals one frame.
    private func handleIncoming(_ data: Data) {
        inbox.append(contentsOf: data)
        while inbox.count >= 8 {
            guard inbox[0] == 0x4D, inbox[1] == 0x50, inbox[2] == 0x4E, inbox[3] == 0x4C else {
                inbox.removeFirst()
                continue
            }
            // Length is u16; the bridge keeps each JPEG under 64 KB.
            let length = Int(inbox[6]) | (Int(inbox[7]) << 8)
            guard length <= 65000 else {
                inbox.removeFirst()
                continue
            }
            guard inbox.count >= 8 + length else { return }
            let type = inbox[5]
            let payload = Array(inbox[8..<(8 + length)])
            inbox.removeFirst(8 + length)
            if type == FrameType.ping.rawValue, let connection = self.connection {
                send(encodeFrame(.pong, Data()), on: connection)
            } else if type == FrameType.video.rawValue {
                // Decoding happens in VideoSink's own queue; the network queue
                // only hands over the bytes so frames keep flowing.
                onVideo?(Data(payload))
                if !deliveredVideo {
                    deliveredVideo = true
                    DispatchQueue.main.async { [weak self] in
                        self?.onVideoStarted?()
                    }
                }
            }
        }
    }

    private func send(_ frame: Data, on connection: NWConnection) {
        connection.send(content: frame, completion: .contentProcessed { error in
            if let error {
                NSLog("send failed: \(error)")
            }
        })
    }
}
