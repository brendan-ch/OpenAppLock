//
//  LogMerge.swift
//  OpenAppLock
//

import Foundation

/// Merges the per-process daily files for one day into a single chronological
/// timeline. Sorting on the 24-char UTC timestamp prefix is exact because every
/// line carries a fixed-width UTC stamp; ties keep file order then within-file
/// order, so the merge is fully deterministic and stable.
enum LogMerge {
    static func merge(perFile: [[String]]) -> [String] {
        var indexed: [(key: String, file: Int, line: Int, text: String)] = []
        for (fileIndex, lines) in perFile.enumerated() {
            for (lineIndex, text) in lines.enumerated() {
                indexed.append((LogTimestamp.prefix(ofLine: text), fileIndex, lineIndex, text))
            }
        }
        indexed.sort { lhs, rhs in
            if lhs.key != rhs.key { return lhs.key < rhs.key }
            if lhs.file != rhs.file { return lhs.file < rhs.file }
            return lhs.line < rhs.line
        }
        return indexed.map(\.text)
    }
}
