//
//  BZip2.swift
//  IceNomad
//
//  A pure-Swift bzip2 DEcompressor — no system library linking required.
//  NomadNet (via RNS.Resource) auto-compresses any response that
//  benefits from it, using Python's stdlib `bz2`, so real page bodies
//  delivered over the Resource transfer arrive bzip2-compressed more
//  often than not.
//
//  Implements the standard bzip2 block format: Huffman-coded symbol
//  groups -> inverse MTF + zero-run (RUNA/RUNB) decoding -> inverse
//  Burrows-Wheeler transform (via the block's origPtr) -> inverse RLE1
//  (runs of 4+ identical bytes were collapsed to 4 bytes + a count byte).
//  Verified against real bzip2-compressed fixtures (this machine's
//  `bzip2` and `python3 -m bz2`), not just written from spec.
//

import Foundation

enum BZip2 {

    enum BZip2Error: Error {
        case badMagic
        case unsupportedBlockSize
        case badBlockMagic
        case randomizedBlockUnsupported
        case malformedHuffmanTable
        case malformedData
        case crcMismatch
    }


    static func decompress(_ data: Data) throws -> Data {

        var reader = BitReader(data: data)

        guard reader.readByte() == UInt8(ascii: "B"),
              reader.readByte() == UInt8(ascii: "Z"),
              reader.readByte() == UInt8(ascii: "h")
        else {
            throw BZip2Error.badMagic
        }

        guard let levelByte = reader.readByte(),
              (UInt8(ascii: "1")...UInt8(ascii: "9")).contains(levelByte)
        else {
            throw BZip2Error.unsupportedBlockSize
        }

        let blockSize100k = Int(levelByte - UInt8(ascii: "0"))
        let maxBlockBytes = blockSize100k * 100_000

        var output = Data()

        while true {

            let magic = try reader.readBits(48)

            if magic == 0x177245385090 {
                // End-of-stream marker, followed by a 32-bit combined CRC we don't verify.
                _ = try? reader.readBits(32)
                break
            }

            guard magic == 0x314159265359 else {
                throw BZip2Error.badBlockMagic
            }

            _ = try reader.readBits(32) // per-block CRC — not verified (no cheap incremental CRC needed for correctness here)

            let randomized = try reader.readBits(1)
            guard randomized == 0 else {
                // Deprecated, and no modern encoder (including Python's
                // bz2, which is what NomadNet uses) ever sets this.
                throw BZip2Error.randomizedBlockUnsupported
            }

            let origPtr = Int(try reader.readBits(24))

            let block = try decodeBlock(reader: &reader, origPtr: origPtr, maxBlockBytes: maxBlockBytes)
            output.append(block)
        }

        return output
    }


    // MARK: - Block decode

    private static func decodeBlock(reader: inout BitReader, origPtr: Int, maxBlockBytes: Int) throws -> Data {

        // MARK: Mapping table (which of the 256 byte values are used)

        let usedGroups = try reader.readBits(16)
        var usedBytes: [UInt8] = []

        for group in 0..<16 {

            guard (usedGroups >> (15 - group)) & 1 == 1 else {
                continue
            }

            let bitmap = try reader.readBits(16)

            for bit in 0..<16 {
                if (bitmap >> (15 - bit)) & 1 == 1 {
                    usedBytes.append(UInt8(group * 16 + bit))
                }
            }
        }

        guard !usedBytes.isEmpty else {
            throw BZip2Error.malformedData
        }

        let alphaSize = usedBytes.count + 2 // + RUNA/RUNB, EOB is alphaSize-1

        // MARK: Selectors

        let nGroups = Int(try reader.readBits(3))
        guard (2...6).contains(nGroups) else {
            throw BZip2Error.malformedHuffmanTable
        }

        let nSelectors = Int(try reader.readBits(15))
        var mtfSelectors: [Int] = []
        mtfSelectors.reserveCapacity(nSelectors)

        for _ in 0..<nSelectors {

            var j = 0
            while try reader.readBits(1) == 1 {
                j += 1
                if j >= nGroups {
                    throw BZip2Error.malformedHuffmanTable
                }
            }
            mtfSelectors.append(j)
        }

        var groupOrder = Array(0..<nGroups)
        var selectors: [Int] = []
        selectors.reserveCapacity(nSelectors)

        for mtfIndex in mtfSelectors {
            let value = groupOrder[mtfIndex]
            groupOrder.remove(at: mtfIndex)
            groupOrder.insert(value, at: 0)
            selectors.append(value)
        }

        // MARK: Huffman tables (per group: delta-encoded code lengths)

        var tables: [HuffmanTable] = []
        tables.reserveCapacity(nGroups)

        for _ in 0..<nGroups {

            var lengths: [Int] = []
            lengths.reserveCapacity(alphaSize)

            var curr = Int(try reader.readBits(5))

            for _ in 0..<alphaSize {

                while true {

                    guard curr >= 1, curr <= 20 else {
                        throw BZip2Error.malformedHuffmanTable
                    }

                    guard try reader.readBits(1) == 1 else {
                        break
                    }

                    if try reader.readBits(1) == 0 {
                        curr += 1
                    } else {
                        curr -= 1
                    }
                }

                lengths.append(curr)
            }

            tables.append(try HuffmanTable(lengths: lengths))
        }

        // MARK: Symbol stream -> inverse MTF + zero-run decode

        var mtf = usedBytes
        var bwtBytes = [UInt8]()
        bwtBytes.reserveCapacity(maxBlockBytes)

        let eob = alphaSize - 1
        var groupPos = 0    // position within the current 50-symbol group
        var selectorIndex = 0
        var currentTable = try currentHuffmanTable(tables: tables, selectors: selectors, selectorIndex: &selectorIndex, groupPos: &groupPos)

        var runLength = 0
        var runBit = 0 // 2^k multiplier for the bijective base-2 RUNA/RUNB run-length encoding

        while true {

            if groupPos == 50 {
                groupPos = 0
                currentTable = try currentHuffmanTable(tables: tables, selectors: selectors, selectorIndex: &selectorIndex, groupPos: &groupPos)
            }

            let symbol = try currentTable.decode(reader: &reader)
            groupPos += 1

            if symbol == 0 || symbol == 1 { // RUNA / RUNB

                runLength += (symbol == 0 ? 1 : 2) << runBit
                runBit += 1
                continue
            }

            if runLength > 0 {

                guard bwtBytes.count + runLength <= maxBlockBytes else {
                    throw BZip2Error.malformedData
                }

                bwtBytes.append(contentsOf: repeatElement(mtf[0], count: runLength))
                runLength = 0
                runBit = 0
            }

            if symbol == eob {
                break
            }

            // Literal symbol: 1-based MTF index (2 -> index 1, since 0/1 are RUNA/RUNB).
            let mtfIndex = symbol - 1
            guard mtfIndex < mtf.count else {
                throw BZip2Error.malformedData
            }

            let value = mtf[mtfIndex]
            mtf.remove(at: mtfIndex)
            mtf.insert(value, at: 0)

            guard bwtBytes.count < maxBlockBytes else {
                throw BZip2Error.malformedData
            }
            bwtBytes.append(value)
        }

        // MARK: Inverse Burrows-Wheeler transform

        let recovered = try inverseBWT(bwtBytes, origPtr: origPtr)

        // MARK: Inverse RLE1 (runs of 4+ identical bytes collapsed to 4 bytes + a count byte)

        return inverseRLE1(recovered)
    }


    private static func currentHuffmanTable(tables: [HuffmanTable], selectors: [Int], selectorIndex: inout Int, groupPos: inout Int) throws -> HuffmanTable {

        guard selectorIndex < selectors.count else {
            throw BZip2Error.malformedData
        }

        let table = tables[selectors[selectorIndex]]
        selectorIndex += 1
        return table
    }


    // MARK: - Inverse Burrows-Wheeler transform
    //
    // Standard next-vector construction: for each output position, the
    // BWT column's stable-sorted rank tells you which input row maps to
    // it. origPtr identifies where to start reading.

    private static func inverseBWT(_ bwt: [UInt8], origPtr: Int) throws -> [UInt8] {

        let n = bwt.count

        guard n > 0, origPtr >= 0, origPtr < n else {
            return []
        }

        var counts = [Int](repeating: 0, count: 256)
        for byte in bwt {
            counts[Int(byte)] += 1
        }

        var totals = [Int](repeating: 0, count: 256)
        var sum = 0
        for i in 0..<256 {
            totals[i] = sum
            sum += counts[i]
        }

        var next = [Int](repeating: 0, count: n)
        var seen = [Int](repeating: 0, count: 256)

        for i in 0..<n {
            let byte = Int(bwt[i])
            next[totals[byte] + seen[byte]] = i
            seen[byte] += 1
        }

        var output = [UInt8]()
        output.reserveCapacity(n)

        var p = next[origPtr]
        for _ in 0..<n {
            output.append(bwt[p])
            p = next[p]
        }

        return output
    }


    // MARK: - Inverse RLE1

    private static func inverseRLE1(_ input: [UInt8]) -> Data {

        var output = Data()
        output.reserveCapacity(input.count)

        var i = 0
        var runByte: UInt8?
        var runLength = 0

        while i < input.count {

            let byte = input[i]

            if byte == runByte {
                runLength += 1
            } else {
                runByte = byte
                runLength = 1
            }

            output.append(byte)

            if runLength == 4 {

                guard i + 1 < input.count else {
                    break
                }

                let extra = Int(input[i + 1])
                if extra > 0 {
                    output.append(contentsOf: repeatElement(byte, count: extra))
                }

                i += 2
                runByte = nil
                runLength = 0
                continue
            }

            i += 1
        }

        return output
    }
}


// MARK: - Bit reader (MSB-first)

private struct BitReader {

    private let data: Data
    private var byteIndex: Data.Index
    private var bitOffset: Int = 0 // 0 = MSB of current byte

    init(data: Data) {
        self.data = data
        self.byteIndex = data.startIndex
    }

    mutating func readByte() -> UInt8? {
        guard let value = try? readBits(8) else {
            return nil
        }
        return UInt8(value & 0xFF)
    }

    mutating func readBits(_ count: Int) throws -> UInt64 {

        guard count <= 64 else {
            throw BZip2.BZip2Error.malformedData
        }

        var result: UInt64 = 0
        var remaining = count

        while remaining > 0 {

            guard byteIndex < data.endIndex else {
                throw BZip2.BZip2Error.malformedData
            }

            let byte = data[byteIndex]
            let bitsLeftInByte = 8 - bitOffset
            let take = min(bitsLeftInByte, remaining)

            let shift = bitsLeftInByte - take
            let mask: UInt8 = take == 8 ? 0xFF : (UInt8(1 << take) - 1)
            let bits = (byte >> shift) & mask

            result = (result << take) | UInt64(bits)
            remaining -= take
            bitOffset += take

            if bitOffset == 8 {
                bitOffset = 0
                byteIndex = data.index(after: byteIndex)
            }
        }

        return result
    }
}


// MARK: - Canonical Huffman decode table

private struct HuffmanTable {

    // Bit-by-bit tree walk via a dictionary keyed by (length, code) —
    // simple and correct; bzip2 alphabets are tiny (<= 258 symbols,
    // lengths <= 20 bits) so this is plenty fast for page-sized data.
    private var codes: [Int: [UInt64: Int]] = [:] // length -> code -> symbol
    private let minLength: Int
    private let maxLength: Int

    init(lengths: [Int]) throws {

        guard let minLen = lengths.min(), let maxLen = lengths.max(), minLen >= 1, maxLen <= 20 else {
            throw BZip2.BZip2Error.malformedHuffmanTable
        }

        minLength = minLen
        maxLength = maxLen

        var code: UInt64 = 0
        var perLength: [Int: [UInt64: Int]] = [:]

        for length in minLen...maxLen {

            var table: [UInt64: Int] = [:]

            for (symbol, symbolLength) in lengths.enumerated() where symbolLength == length {
                table[code] = symbol
                code += 1
            }

            perLength[length] = table
            code <<= 1
        }

        codes = perLength
    }

    func decode(reader: inout BitReader) throws -> Int {

        var code: UInt64 = 0

        for length in 1...maxLength {

            code = (code << 1) | (try reader.readBits(1))

            if length < minLength {
                continue
            }

            if let symbol = codes[length]?[code] {
                return symbol
            }
        }

        throw BZip2.BZip2Error.malformedData
    }
}
