import Foundation

/// One PC with two panels: 1P listens on 24870, 2P on 24880. The PC bridge
/// opens one TCP forward per port, so each tablet pairs itself by slot.
let panelServicePort1P: UInt16 = 24870
let panelServicePort2P: UInt16 = 24880

func panelPort(for slot: Int) -> UInt16 {
    slot == 2 ? panelServicePort2P : panelServicePort1P
}

/// Frame types used by this demo. The complete app also has touch, outer
/// button, system key, LED and reader-text frames; this shell only needs the
/// handshake and the video stream.
enum FrameType: UInt8 {
    case ping = 0x02
    case pong = 0x03
    case control = 0x07
    case video = 0x10
}

let protocolVersion: UInt8 = 1

/// Wire format, little endian:
///   "MPNL" | version:u8 | type:u8 | length:u16 | payload
func encodeFrame(_ type: FrameType, _ payload: Data) -> Data {
    var frame = Data("MPNL".utf8)
    frame.append(protocolVersion)
    frame.append(type.rawValue)
    var length = UInt16(payload.count).littleEndian
    withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
    frame.append(payload)
    return frame
}

/// Control payload is [command, value]. 1/1 asks the PC to start mirroring
/// the game window, 1/0 stops it.
func encodeVideoControl(_ on: Bool) -> Data {
    encodeFrame(.control, Data([1, on ? 1 : 0]))
}

/// Command 2 reports which slot the tablet is set to (1 or 2), so the bridge
/// can warn when a panel is on the wrong port.
func encodeSlotControl(_ slot: Int) -> Data {
    encodeFrame(.control, Data([2, UInt8(max(1, min(2, slot)))]))
}
