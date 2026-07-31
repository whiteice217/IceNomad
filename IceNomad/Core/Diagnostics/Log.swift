//
//  Log.swift
//  IceNomad
//
//  Central os.Logger definitions, one per subsystem. Replaces the
//  ad-hoc print() statements accumulated during live protocol
//  debugging — those either fired on every packet (worthless once the
//  network is actually busy, which it always is: announces alone
//  arrive every few seconds) or leaked plaintext message content to
//  the console. Unified logging is filterable by category in
//  Console.app/the Xcode console, and safe by default (interpolated
//  values are redacted unless explicitly marked `.public`).
//

import OSLog

enum Log {

    private static let subsystem = "com.saltycapn.icenomad.IceNomad"

    static let network = Logger(subsystem: subsystem, category: "network")
    static let reticulum = Logger(subsystem: subsystem, category: "reticulum")
    static let lxmf = Logger(subsystem: subsystem, category: "lxmf")
    static let identity = Logger(subsystem: subsystem, category: "identity")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let system = Logger(subsystem: subsystem, category: "system")
}
