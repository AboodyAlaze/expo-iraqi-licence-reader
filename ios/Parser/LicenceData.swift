import Foundation

/// قراءة وجه البطاقة: MRZ (موثوق) + VIZ (تقريبي).
///
/// MRZ موثوق: رقم التحقق + اتفاق عدة إطارات.
/// VIZ تقريبي: بلا تحقق إطلاقاً.
struct LicenceFront {
    var mrz: MrzResult?
    var viz: VizResult
    var mrzMatchesViz: Bool

    var licenceNumber: String {
        if let m = mrz, !m.licenceNumber.isEmpty { return m.licenceNumber }
        return viz.licenceNumber
    }

    var nationalNumber: String {
        if let m = mrz, !m.nationalNumber.isEmpty { return m.nationalNumber }
        return viz.nationalNumber
    }

    var verified: Bool { mrz != nil }
}

enum LicenceParser {

    /// قراءة الوجه (MRZ + VIZ)
    static func parseFront(_ rawText: String) -> LicenceFront {
        let mrz = MrzParser.extract(rawText)
        let viz = VizParser.parse(rawText)

        let matches = mrz != nil
            && !viz.licenceNumber.isEmpty
            && viz.licenceNumber == mrz!.licenceNumber

        return LicenceFront(mrz: mrz, viz: viz, mrzMatchesViz: matches)
    }

    /// قراءة الظهر — نفضّل الإحداثيات، وإذا ما نجحت نرجع للنص الخام
    static func parseBack(blocks: [TextBlock], rawText: String) -> [LicenceCategory] {
        let byGeometry = CategoryParser.parseBlocks(blocks)
        if !byGeometry.isEmpty { return byGeometry }
        return CategoryParser.parse(rawText)
    }
}
