import Foundation
import SwiftUI
import UniformTypeIdentifiers
import mp3ChapterReader

extension FrameFlags {
    var summary: String {
        var values: [String] = []

        if isTagAlterPreservation { values.append("tag alter preservation") }
        if isFileAlterPreservation { values.append("file alter preservation") }
        if isReadOnly { values.append("read only") }
        if isGroupingIdentity { values.append("grouped") }
        if isCompressed { values.append("compressed") }
        if isEncrypted { values.append("encrypted") }
        if isUnsynchronized { values.append("unsynchronized") }
        if hasDataLengthIndicator { values.append("data length indicator") }
        if let groupIdentifier { values.append("group \(groupIdentifier)") }
        if let encryptionMethod { values.append("encryption \(encryptionMethod)") }
        if let dataLengthIndicator { values.append("data length \(dataLengthIndicator)") }
        if let decompressedSize { values.append("decompressed \(decompressedSize)") }

        return values.isEmpty ? "None" : values.joined(separator: ", ")
    }
}

extension View {
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

extension Bool {
    var yesNo: String {
        self ? "Yes" : "No"
    }
}

extension Int {
    var id3OffsetDescription: String {
        self == Int(UInt32.max) ? "Not set" : "\(self)"
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension ByteCountFormatter {
    static let id3: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .file
        formatter.includesActualByteCount = true
        return formatter
    }()
}

extension UTType {
    static let mp3 = UTType(filenameExtension: "mp3") ?? .audio
}

func describe(_ value: Any) -> String {
    switch value {
    case let data as Data:
        return "\(data.count) bytes"
    case let string as String:
        return string
    case let number as NSNumber:
        return number.stringValue
    case let array as [Any]:
        return array.map(describe).joined(separator: "\n")
    case let dict as [String: Any]:
        return dict
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \(describe($0.value))" }
            .joined(separator: "\n")
    default:
        return String(describing: value)
    }
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite else {
        return "0:00"
    }

    let total = max(0, Int(seconds.rounded()))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    return String(format: "%d:%02d", minutes, seconds)
}

func readSynchsafeInt(_ data: Data, at offset: Int) -> Int {
    guard offset + 3 < data.count else {
        return 0
    }

    return (Int(data[offset]) << 21)
        | (Int(data[offset + 1]) << 14)
        | (Int(data[offset + 2]) << 7)
        | Int(data[offset + 3])
}

func readUInt32BigEndian(_ data: Data, at offset: Int) -> Int {
    guard offset + 3 < data.count else {
        return 0
    }

    return (Int(data[offset]) << 24)
        | (Int(data[offset + 1]) << 16)
        | (Int(data[offset + 2]) << 8)
        | Int(data[offset + 3])
}
