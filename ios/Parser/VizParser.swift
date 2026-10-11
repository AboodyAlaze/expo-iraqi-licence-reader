import Foundation

/// قراءة وجه البطاقة (Visual Inspection Zone).
///
/// تحذير: هذي المنطقة ما فيها أرقام تحقق — على عكس الـ MRZ.
/// أي غلطة بالـ OCR راح تمر بصمت.
struct VizResult {
    var nameLatin = ""
    var nameArabic = ""
    var dateOfBirth = ""
    var dateOfIssue = ""
    var dateOfExpiry = ""
    var issuingOffice = ""
    var nationalNumber = ""
    var nationality = ""
    var bloodType = ""
    var licenceNumber = ""
    var categories = ""
    var address = ""
    var datesFound: [String] = []
    var allLines: [String] = []

    /// مؤشر غنى القراءة — نستعمله لاختيار أفضل إطار
    var richness: Int {
        [nameLatin, nameArabic, dateOfBirth, dateOfIssue, dateOfExpiry,
         nationalNumber, bloodType, licenceNumber, categories]
            .filter { !$0.isEmpty }.count
    }
}

enum VizParser {

    private static let headerLatin = [
        "KURDISTAN", "MINISTRY", "INTERIOR", "DRIVING",
        "LICENCE", "LICENSE", "REGION", "REPUBLIC", "TRAFFIC"
    ]

    private static let headerArabic = [
        "إقليم", "كوردستان", "كۆمارى", "وزارة", "الداخلية", "وەزارەتى",
        "إجازة", "السياقة", "العراق", "عێراق", "جمهورية",
        "مۆڵەتی", "شۆفێری", "ناوخۆ", "مولەتى", "شوفێرى"
    ]

    static func parse(_ rawText: String) -> VizResult {
        let lines = rawText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var r = VizResult()
        r.allLines = lines

        // نربط كل تاريخ برقم حقله: 3=ميلاد 4a=إصدار 4b=انتهاء
        var labelled: [String: String] = [:]
        var unlabelled: [String] = []
        var addressParts: [String] = []

        for line in lines {
            let lineTag = match(line, "^\\s*(\\d{1,2}[a-d]?)\\s*[.,]", 1)?.lowercased()
            let clean = replace(line, "^\\s*(?:\\d{1,2}[a-d]?\\s*[.,]\\s*)+", "")
                .trimmingCharacters(in: .whitespaces)

            // التواريخ مع رقم الحقل القريب
            let ns = line as NSString
            if let re = try? NSRegularExpression(
                pattern: "(\\d{2})\\s*[./\\-]\\s*(\\d{2})\\s*[./\\-]\\s*(\\d{4})"
            ) {
                for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                    let d = ns.substring(with: m.range(at: 1))
                    let mo = ns.substring(with: m.range(at: 2))
                    let y = ns.substring(with: m.range(at: 3))
                    let date = "\(d)/\(mo)/\(y)"

                    let before = ns.substring(to: m.range.location)
                    let tag = match(before, "(\\d{1,2}[a-d]?)\\s*[.,]\\s*$", 1)?.lowercased()
                        ?? lineTag

                    switch tag {
                    case "3": if labelled["3"] == nil { labelled["3"] = date }
                    case "4a": if labelled["4a"] == nil { labelled["4a"] = date }
                    case "4b": if labelled["4b"] == nil { labelled["4b"] = date }
                    default: if !unlabelled.contains(date) { unlabelled.append(date) }
                    }
                }
            }

            if r.bloodType.isEmpty,
               let b = match(line, "\\b(AB|A|B|O)\\s?([+\\-])", 0) {
                r.bloodType = b.replacingOccurrences(of: " ", with: "")
            }

            if r.nationality.isEmpty {
                if clean.uppercased().contains("IRAQI") {
                    r.nationality = "IRAQI"
                } else if clean.contains("عراقي") || clean.contains("عێراقی") {
                    r.nationality = "عراقي"
                }
            }

            if r.issuingOffice.isEmpty, clean.lowercased().contains("traffic") {
                r.issuingOffice = clean
            }

            if r.nameLatin.isEmpty,
               matches(clean, "^[A-Z][A-Z'\\- ]{5,}$"),
               !headerLatin.contains(where: { clean.contains($0) }) {
                r.nameLatin = clean
            }

            if hasArabic(clean), !clean.contains(where: { $0.isNumber }), clean.count > 2,
               !headerArabic.contains(where: { clean.contains($0) }) {
                if r.nameArabic.isEmpty {
                    r.nameArabic = clean
                } else {
                    addressParts.append(clean)
                }
            }

            if r.nationalNumber.isEmpty,
               let n = match(line, "\\b\\d{12,13}\\b", 0) {
                r.nationalNumber = n
            }

            if r.licenceNumber.isEmpty,
               let l = match(line, "\\b([A-Z])\\s?(\\d{8})\\b", 0) {
                r.licenceNumber = l.replacingOccurrences(of: " ", with: "")
            }

            if r.categories.isEmpty,
               let c = match(clean, "^\\s*([A-D]\\d?\\+?(?:\\s+[A-D]\\d?\\+?)*)\\s*$", 1) {
                let v = c.trimmingCharacters(in: .whitespaces)
                if v.count > 1 || ["A", "B", "C", "D"].contains(v) {
                    r.categories = v
                }
            }
        }

        // الحقول المرقّمة أولاً، والباقي بالترتيب الزمني
        let all = Array(Set(Array(labelled.values) + unlabelled))
        let sorted = all.sorted { yearOf($0) < yearOf($1) }

        r.dateOfBirth = labelled["3"] ?? ""
        r.dateOfIssue = labelled["4a"] ?? ""
        r.dateOfExpiry = labelled["4b"] ?? ""

        if r.dateOfBirth.isEmpty, let f = sorted.first { r.dateOfBirth = f }

        let afterDob = sorted.filter { $0 != r.dateOfBirth }
        if r.dateOfExpiry.isEmpty, let l = afterDob.last { r.dateOfExpiry = l }
        if r.dateOfIssue.isEmpty, afterDob.count >= 2 {
            r.dateOfIssue = afterDob[afterDob.count - 2]
        }

        // الانتهاء لازم يكون بعد الإصدار
        if !r.dateOfIssue.isEmpty, !r.dateOfExpiry.isEmpty,
           yearOf(r.dateOfIssue) > yearOf(r.dateOfExpiry) {
            let t = r.dateOfIssue
            r.dateOfIssue = r.dateOfExpiry
            r.dateOfExpiry = t
        }

        r.datesFound = sorted
        r.address = addressParts.joined(separator: "، ")
        return r
    }

    // MARK: أدوات

    private static func hasArabic(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
    }

    private static func yearOf(_ d: String) -> Int { Int(d.suffix(4)) ?? 0 }

    private static func match(_ s: String, _ pattern: String, _ group: Int) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length))
        else { return nil }
        guard group < m.numberOfRanges, m.range(at: group).location != NSNotFound
        else { return nil }
        return ns.substring(with: m.range(at: group))
    }

    private static func matches(_ s: String, _ pattern: String) -> Bool {
        match(s, pattern, 0) != nil
    }

    private static func replace(_ s: String, _ pattern: String, _ with: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        return re.stringByReplacingMatches(
            in: s, range: NSRange(location: 0, length: ns.length), withTemplate: with
        )
    }
}
