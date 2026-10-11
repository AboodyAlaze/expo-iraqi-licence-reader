package expo.modules.iraqilicencereader.parser

/**
 * قراءة وجه البطاقة: MRZ (موثوق) + VIZ (تقريبي).
 *
 * MRZ موثوق: رقم التحقق + اتفاق عدة إطارات.
 * VIZ تقريبي: بلا تحقق إطلاقاً.
 */
data class LicenceFront(
    val mrz: MrzResult?,
    val viz: VizResult,
    val mrzMatchesViz: Boolean
) {
    val licenceNumber: String
        get() = mrz?.licenceNumber?.takeIf { it.isNotEmpty() } ?: viz.licenceNumber

    val nationalNumber: String
        get() = mrz?.nationalNumber?.takeIf { it.isNotEmpty() } ?: viz.nationalNumber

    val verified: Boolean get() = mrz != null
}

object LicenceParser {

    /** قراءة الوجه (MRZ + VIZ) */
    fun parseFront(rawText: String): LicenceFront {
        val mrz = MrzParser.extract(rawText)
        val viz = VizParser.parse(rawText)

        val matches = mrz != null &&
            viz.licenceNumber.isNotEmpty() &&
            viz.licenceNumber == mrz.licenceNumber

        return LicenceFront(mrz = mrz, viz = viz, mrzMatchesViz = matches)
    }

    /** قراءة الظهر — نفضّل الإحداثيات، وإذا ما نجحت نرجع للنص الخام */
    fun parseBack(blocks: List<TextBlock>, rawText: String): List<LicenceCategory> {
        val byGeometry = CategoryParser.parseBlocks(blocks)
        if (byGeometry.isNotEmpty()) return byGeometry
        return CategoryParser.parse(rawText)
    }
}
