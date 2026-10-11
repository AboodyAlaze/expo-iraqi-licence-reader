import Foundation

/// تحويل النتائج لـ JSON نصي — نفس شكل نسخة أندرويد بالضبط،
/// فـ TypeScript يحلّل النص بنفس الطريقة على المنصتين.
enum LicenceJson {

    static func front(_ f: LicenceFront) -> String {
        var mrz: Any = NSNull()
        if let m = f.mrz {
            mrz = [
                "licenceNumber": m.licenceNumber,
                "nationalNumber": m.nationalNumber,
                "raw": m.raw,
                "variant": m.variantName,
            ]
        }

        let v = f.viz
        let viz: [String: Any] = [
            "nameLatin": v.nameLatin,
            "nameArabic": v.nameArabic,
            "dateOfBirth": v.dateOfBirth,
            "dateOfIssue": v.dateOfIssue,
            "dateOfExpiry": v.dateOfExpiry,
            "issuingOffice": v.issuingOffice,
            "nationalNumber": v.nationalNumber,
            "nationality": v.nationality,
            "bloodType": v.bloodType,
            "licenceNumber": v.licenceNumber,
            "categories": v.categories,
            "address": v.address,
            "allLines": v.allLines,
        ]

        let obj: [String: Any] = [
            "verified": f.verified,
            "mrz": mrz,
            "mrzMatchesViz": f.mrzMatchesViz,
            "licenceNumber": f.licenceNumber,
            "nationalNumber": f.nationalNumber,
            "viz": viz,
        ]
        return serialize(obj)
    }

    static func back(_ cats: [LicenceCategory]) -> String {
        let arr: [[String: String]] = cats.map {
            ["code": $0.code, "issueDate": $0.issueDate, "expiryDate": $0.expiryDate]
        }
        return serialize(arr)
    }

    private static func serialize(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let s = String(data: data, encoding: .utf8)
        else { return "null" }
        return s
    }
}
