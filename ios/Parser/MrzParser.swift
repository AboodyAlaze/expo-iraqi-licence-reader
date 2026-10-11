import Foundation

/// المنطقة المقروءة آلياً من إجازة السياقة.
struct MrzResult {
    let licenceNumber: String
    /// فاضي بالإصدار الاتحادي — موجود بإصدار الإقليم فقط
    let nationalNumber: String
    let raw: String
    let variant: Variant

    enum Variant {
        case withNational
        case licenceOnly
    }

    /// نفس القيم المستعملة بنسخة أندرويد و TypeScript
    var variantName: String {
        switch variant {
        case .withNational: return "KURDISTAN"
        case .licenceOnly: return "FEDERAL"
        }
    }
}

/// تركيبة السطر (30 خانة) — نسختان:
///
///   إقليم:  D< D12345678 1234567890123 <<<<< 9
///   اتحادي: D< D12345678 <<<<<<<<<<<<< <<<<< 2
///
/// التحدي مع الاتحادي إن فيه 18 رمز < متتالي، والـ OCR كثير
/// يسقط واحد أو يزيد واحد عند قراءة سلسلة متشابهة طويلة.
///
/// لذلك ما نعتمد على طول ثابت: ندوّر على البداية المميزة
/// (D< + حرف + 8 أرقام)، نشيل كل الـ <، ونشوف شنو تبقى.
enum MrzParser {

    static func extract(_ rawText: String) -> MrzResult? {
        let lines = rawText
            .uppercased()
            .components(separatedBy: .newlines)
            .map { normalise($0) }
            .filter { $0.count >= 11 }

        for line in lines {
            if let r = parseFlexible(line) { return r }
        }

        // محاولة أخيرة: الأسطر ملصوقة
        return parseFlexible(lines.joined())
    }

    /// ينظّف السطر من الضجيج.
    /// K و « و ‹ من أشيع أخطاء OCR لرمز <
    private static func normalise(_ line: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<")
        let swapped = line
            .replacingOccurrences(of: "«", with: "<")
            .replacingOccurrences(of: "‹", with: "<")
            .replacingOccurrences(of: "K", with: "<")
        return String(swapped.unicodeScalars.filter { allowed.contains($0) })
    }

    private static func parseFlexible(_ line: String) -> MrzResult? {
        guard let regex = try? NSRegularExpression(pattern: "D<([A-Z]\\d{8})") else {
            return nil
        }

        let ns = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))

        for m in matches {
            let licence = ns.substring(with: m.range(at: 1))
            let tailStart = m.range.location + m.range.length
            guard tailStart < ns.length else { continue }

            let tail = ns.substring(from: tailStart)
                .replacingOccurrences(of: "<", with: "")

            // اتحادي — ما تبقى غير رقم التحقق
            if tail.count == 1, let c = tail.first, c.isNumber {
                let rebuilt = buildLine(licence: licence, national: "", check: c)
                let body = String(rebuilt.prefix(29))
                if CheckDigit.verify(body, expected: c) {
                    return MrzResult(
                        licenceNumber: licence,
                        nationalNumber: "",
                        raw: rebuilt,
                        variant: .licenceOnly
                    )
                }
            }

            // إقليم — 13 رقم وطني + رقم تحقق
            if tail.count >= 14 {
                let head = String(tail.prefix(14))
                if head.allSatisfy({ $0.isNumber }) {
                    let national = String(head.prefix(13))
                    let check = head[head.index(head.startIndex, offsetBy: 13)]
                    let rebuilt = buildLine(licence: licence, national: national, check: check)
                    let body = String(rebuilt.prefix(29))
                    if CheckDigit.verify(body, expected: check) {
                        return MrzResult(
                            licenceNumber: licence,
                            nationalNumber: national,
                            raw: rebuilt,
                            variant: .withNational
                        )
                    }
                }
            }
        }
        return nil
    }

    /// يعيد بناء السطر بالصيغة القياسية 30 خانة
    private static func buildLine(licence: String, national: String, check: Character) -> String {
        var nat = national
        while nat.count < 13 { nat += "<" }
        return "D<" + licence + nat + "<<<<<" + String(check)
    }
}
