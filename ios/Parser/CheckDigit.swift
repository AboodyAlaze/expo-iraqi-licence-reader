import Foundation

/// خوارزمية رقم التحقق من معيار ICAO 9303.
/// إجازة السياقة العراقية تستعملها رغم إن تركيبة الـ MRZ مالتها غير قياسية.
enum CheckDigit {

    private static let weights = [7, 3, 1]

    static func compute(_ input: String) -> Character? {
        var sum = 0
        for (i, c) in input.enumerated() {
            let v: Int
            if c.isNumber {
                v = c.wholeNumberValue ?? 0
            } else if c == "<" {
                v = 0
            } else if let a = c.asciiValue, c.isLetter {
                v = Int(a) - 65 + 10
            } else {
                return nil
            }
            sum += v * weights[i % 3]
        }
        return Character(String(sum % 10))
    }

    static func verify(_ body: String, expected: Character) -> Bool {
        compute(body) == expected
    }
}
