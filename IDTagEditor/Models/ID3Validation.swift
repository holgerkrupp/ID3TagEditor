import Foundation

enum ID3DiagnosticSeverity: String {
    case warning = "Warning"
    case error = "Error"
}

struct ID3ValidationDiagnostic: Identifiable, Equatable {
    let id = UUID()
    var severity: ID3DiagnosticSeverity
    var message: String
    var byteRange: Range<Int>?

    var isFatal: Bool {
        severity == .error
    }
}

struct ID3ValidationResult {
    var diagnostics: [ID3ValidationDiagnostic]

    var hasFatalErrors: Bool {
        diagnostics.contains { $0.isFatal }
    }

    var isValid: Bool {
        !hasFatalErrors
    }
}

enum ID3TagValidator {
    static func validate(tagData data: Data) -> ID3ValidationResult {
        var diagnostics: [ID3ValidationDiagnostic] = []

        guard data.count >= 10 else {
            return ID3ValidationResult(diagnostics: [
                .init(severity: .error, message: "ID3 header is shorter than 10 bytes.", byteRange: 0..<max(data.count, 1))
            ])
        }

        guard data.prefix(3) == Data("ID3".utf8) else {
            diagnostics.append(.init(severity: .error, message: "Missing ID3 file identifier.", byteRange: 0..<3))
            return ID3ValidationResult(diagnostics: diagnostics)
        }

        let version = Int(data[3])
        if version != 3 && version != 4 {
            diagnostics.append(.init(severity: .error, message: "Only ID3v2.3 and ID3v2.4 tags can be edited.", byteRange: 3..<4))
        }

        let flags = data[5]
        let declaredBodySize = readSynchsafeInt(data, at: 6)
        let hasFooter = version == 4 && flags & 0x10 != 0
        let expectedTagSize = 10 + declaredBodySize + (hasFooter ? 10 : 0)
        if expectedTagSize > data.count {
            diagnostics.append(.init(severity: .error, message: "Declared tag size extends past available ID3 bytes.", byteRange: 6..<10))
        } else if expectedTagSize < data.count {
            diagnostics.append(.init(severity: .warning, message: "ID3 byte buffer contains trailing bytes outside the declared tag size.", byteRange: expectedTagSize..<data.count))
        }

        var offset = 10
        let frameLimit = min(data.count, 10 + declaredBodySize)

        if flags & 0x40 != 0 {
            guard offset + 4 <= frameLimit else {
                diagnostics.append(.init(severity: .error, message: "Extended header is truncated.", byteRange: offset..<min(data.count, offset + 4)))
                return ID3ValidationResult(diagnostics: diagnostics)
            }
            let extendedSize = version == 4 ? readSynchsafeInt(data, at: offset) : readUInt32BigEndian(data, at: offset) + 4
            if extendedSize <= 0 || offset + extendedSize > frameLimit {
                diagnostics.append(.init(severity: .error, message: "Extended header size is invalid.", byteRange: offset..<min(data.count, offset + 4)))
                return ID3ValidationResult(diagnostics: diagnostics)
            }
            offset += extendedSize
        }

        while offset + 10 <= frameLimit {
            let headerRange = offset..<(offset + 10)
            let idData = data[offset..<(offset + 4)]
            if idData.allSatisfy({ $0 == 0 }) {
                break
            }

            let frameID = String(data: idData, encoding: .ascii) ?? ""
            if frameID.count != 4 || !frameID.allSatisfy({ $0.isUppercase || $0.isNumber }) {
                diagnostics.append(.init(severity: .error, message: "Invalid frame identifier.", byteRange: headerRange))
                break
            }

            let bodySize = version == 4 ? readSynchsafeInt(data, at: offset + 4) : readUInt32BigEndian(data, at: offset + 4)
            if bodySize < 0 {
                diagnostics.append(.init(severity: .error, message: "Frame size is invalid.", byteRange: (offset + 4)..<(offset + 8)))
                break
            }

            let bodyStart = offset + 10
            let bodyEnd = bodyStart + bodySize
            if bodyEnd > frameLimit {
                diagnostics.append(.init(severity: .error, message: "Frame \(frameID) extends past the declared tag body.", byteRange: (offset + 4)..<(offset + 8)))
                break
            }

            if frameID == "CHAP" || frameID == "CTOC" {
                validateChapterLikeFrame(id: frameID, data: data, bodyStart: bodyStart, bodyEnd: bodyEnd, diagnostics: &diagnostics)
            }

            offset = bodyEnd
        }

        if offset < frameLimit {
            let padding = data[offset..<frameLimit]
            if !padding.allSatisfy({ $0 == 0 }) {
                diagnostics.append(.init(severity: .warning, message: "Unparsed non-zero bytes remain in the tag body.", byteRange: offset..<frameLimit))
            }
        }

        if hasFooter, 10 + declaredBodySize + 10 <= data.count {
            let footerStart = 10 + declaredBodySize
            if data[footerStart..<(footerStart + 3)] != Data("3DI".utf8) {
                diagnostics.append(.init(severity: .warning, message: "ID3 footer marker is not valid.", byteRange: footerStart..<(footerStart + 3)))
            }
        }

        return ID3ValidationResult(diagnostics: diagnostics)
    }

    private static func validateChapterLikeFrame(
        id: String,
        data: Data,
        bodyStart: Int,
        bodyEnd: Int,
        diagnostics: inout [ID3ValidationDiagnostic]
    ) {
        guard bodyStart < bodyEnd else {
            diagnostics.append(.init(severity: .error, message: "\(id) frame has an empty body.", byteRange: bodyStart..<max(bodyStart + 1, bodyEnd)))
            return
        }

        guard let terminator = data[bodyStart..<bodyEnd].firstIndex(of: 0) else {
            diagnostics.append(.init(severity: .error, message: "\(id) frame is missing its element ID terminator.", byteRange: bodyStart..<bodyEnd))
            return
        }

        let minimumRemaining = id == "CHAP" ? 16 : 2
        if terminator + 1 + minimumRemaining > bodyEnd {
            diagnostics.append(.init(severity: .error, message: "\(id) frame body is truncated.", byteRange: bodyStart..<bodyEnd))
        }
    }
}
