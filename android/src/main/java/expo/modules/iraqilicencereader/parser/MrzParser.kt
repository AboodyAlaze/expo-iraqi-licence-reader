package expo.modules.iraqilicencereader.parser

/** المنطقة المقروءة آلياً من إجازة السياقة */
data class MrzResult(
    val licenceNumber: String,
    /** فاضي بالإصدار الاتحادي — موجود بإصدار الإقليم فقط */
    val nationalNumber: String,
    val raw: String,
    val variant: Variant
) {
    enum class Variant { KURDISTAN, FEDERAL }
}

/**
 * تركيبة السطر (30 خانة) — نسختان:
 *
 *   إقليم:  D< D12345678 1234567890123 <<<<< 9
 *   اتحادي: D< D12345678 <<<<<<<<<<<<< <<<<< 2
 *
 * الاتحادي فيه 18 رمز < متتالي، والـ OCR كثير يسقط واحد أو يزيد واحد.
 * لذلك ما نعتمد على طول ثابت: ندوّر على البداية المميزة
 * (D< + حرف + 8 أرقام)، نشيل كل الـ <، ونشوف شنو تبقى:
 *   رقم واحد → اتحادي،  14 رقم → إقليم (13 وطني + تحقق).
 * ثم نعيد بناء السطر بالصيغة القياسية ونتحقق منه.
 */
object MrzParser {

    private val PATTERN = Regex("""D<([A-Z]\d{8})""")

    fun extract(rawText: String): MrzResult? {
        val lines = rawText
            .uppercase()
            .lines()
            .map { normalise(it) }
            .filter { it.length >= 11 }

        for (line in lines) {
            parseFlexible(line)?.let { return it }
        }
        // أحياناً الـ OCR يقسّم السطر الواحد لقسمين
        return parseFlexible(lines.joinToString(""))
    }

    /** K و « و ‹ من أشيع أخطاء OCR لرمز < */
    private fun normalise(line: String): String = line
        .replace('«', '<')
        .replace('‹', '<')
        .replace('K', '<')
        .replace(Regex("[^A-Z0-9<]"), "")

    private fun parseFlexible(line: String): MrzResult? {
        for (m in PATTERN.findAll(line)) {
            val licence = m.groupValues[1]
            val tail = line.substring(m.range.last + 1).replace("<", "")

            // اتحادي — ما تبقى غير رقم التحقق
            if (tail.length == 1 && tail[0].isDigit()) {
                val rebuilt = buildLine(licence, "", tail[0])
                if (CheckDigit.verify(rebuilt.substring(0, 29), tail[0])) {
                    return MrzResult(licence, "", rebuilt, MrzResult.Variant.FEDERAL)
                }
            }

            // إقليم — 13 رقم وطني + رقم تحقق
            if (tail.length >= 14 && tail.take(14).all { it.isDigit() }) {
                val national = tail.substring(0, 13)
                val check = tail[13]
                val rebuilt = buildLine(licence, national, check)
                if (CheckDigit.verify(rebuilt.substring(0, 29), check)) {
                    return MrzResult(licence, national, rebuilt, MrzResult.Variant.KURDISTAN)
                }
            }
        }
        return null
    }

    private fun buildLine(licence: String, national: String, check: Char): String =
        "D<" + licence + national.padEnd(13, '<') + "<<<<<" + check
}
