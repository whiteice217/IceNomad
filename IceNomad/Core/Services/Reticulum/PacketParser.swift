//
// PacketParser.swift
// IceNomad
//

import Foundation


class PacketParser {

    private var buffer = Data()

    var onFrameReceived: ((ReticulumFrame) -> Void)?



    // MARK: - Receive Data

    func receive(_ data: Data) {

        buffer.append(data)

        extractFrames()
    }



    // MARK: - Frame Extraction
    private func extractFrames() {

        while true {

            // Find Reticulum frame start
            guard let start = buffer.firstIndex(of: 0x7E) else {

                buffer.removeAll()
                return
            }


            // Remove anything before frame marker.
            // NOTE: `start` is a Data.Index, NOT a count — Data's indices
            // do not reset to 0 after mutation, so we must convert it to
            // a relative distance before passing it to removeFirst.
            let leading = buffer.distance(from: buffer.startIndex, to: start)
            if leading > 0 {

                buffer.removeFirst(leading)
            }


            // Need enough bytes for basic header
            guard buffer.count >= 20 else {

                return
            }


            let header = Array(buffer.prefix(19))


            let flags = header[2]


            print(
                "🔎 Frame detected",
                "Flags:",
                String(format: "%02X", flags)
            )


            // Find next frame marker, honoring KISS-style escaping.
            // 0x7D is an escape byte — whatever byte follows it is part of
            // the payload, not a real marker, even if it looks like 0x7E.
            var scan = buffer.index(after: buffer.startIndex)
            var end: Data.Index? = nil

            while scan < buffer.endIndex {

                let byte = buffer[scan]

                if byte == 0x7D {

                    let escaped = buffer.index(after: scan)
                    guard escaped < buffer.endIndex else {
                        // Escape byte is the last byte we have — wait for more data.
                        break
                    }
                    scan = buffer.index(after: escaped)
                    continue
                }

                if byte == 0x7E {
                    end = scan
                    break
                }

                scan = buffer.index(after: scan)
            }

            guard let frameEnd = end else {

                // Wait for more TCP data
                return
            }


            let contentLength = buffer.distance(
                from: buffer.startIndex,
                to: frameEnd
            )

            // Also consume the closing marker itself — this stream sends
            // an independent 0x7E to end each frame (not shared with the
            // next frame's opening marker), so leaving it in the buffer
            // causes the next pass to misread it as a bogus 1-byte frame.
            let totalConsumed = contentLength + 1


            guard buffer.count >= totalConsumed else {

                return
            }


            let rawFrame = Data(
                buffer.prefix(contentLength)
            )


            buffer.removeFirst(totalConsumed)


            let frameData = unescape(rawFrame)


            print(
                "📦 Extracted frame:",
                frameData.count,
                "bytes"
            )


            decode(frameData)
        }
    }



    // MARK: - Unescape

    /// Reverses KISS/HDLC-style escaping: 0x7D 0x5E -> 0x7E, 0x7D 0x5D -> 0x7D.
    /// The leading frame marker (index 0) passes through unchanged.
    private func unescape(_ data: Data) -> Data {

        var result = Data()
        result.reserveCapacity(data.count)

        var i = data.startIndex

        while i < data.endIndex {

            let byte = data[i]

            if byte == 0x7D {

                let next = data.index(after: i)

                guard next < data.endIndex else {
                    // Malformed trailing escape — drop it.
                    break
                }

                switch data[next] {
                case 0x5E:
                    result.append(0x7E)
                case 0x5D:
                    result.append(0x7D)
                default:
                    result.append(data[next])
                }

                i = data.index(after: next)

            } else {

                result.append(byte)
                i = data.index(after: i)
            }
        }

        return result
    }



    // MARK: - Decode Frame

    private func decode(_ data: Data) {


        let frame = ReticulumFrame(
            data: data
        )


        print("🚀 FRAME READY")
        print("Type:", frame.packetType)
        print("Header:", frame.headerType)
        print("Size:", frame.data.count)


        onFrameReceived?(frame)
    }
}
