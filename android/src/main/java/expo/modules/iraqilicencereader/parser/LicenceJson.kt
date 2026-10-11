package expo.modules.iraqilicencereader.parser

/**
 * تحويل النتائج لـ JSON نصي.
 *
 * نرجّع نصاً للـ JS بدل كائن لأن الجسر يبقى بسيطاً، وTypeScript
 * يحلّل النص ويضيف الحقول المشتقة (الوصف العربي وحالة السريان).
 * مكتوب يدوياً بدون org.json حتى يشتغل الكود نفسه بأي مكان.
 */
object LicenceJson {

    fun front(f: LicenceFront): String {
        val mrz = f.mrz?.let {
            obj(
                "licenceNumber" to str(it.licenceNumber),
                "nationalNumber" to str(it.nationalNumber),
                "raw" to str(it.raw),
                "variant" to str(it.variant.name)
            )
        } ?: "null"

        val v = f.viz
        val viz = obj(
            "nameLatin" to str(v.nameLatin),
            "nameArabic" to str(v.nameArabic),
            "dateOfBirth" to str(v.dateOfBirth),
            "dateOfIssue" to str(v.dateOfIssue),
            "dateOfExpiry" to str(v.dateOfExpiry),
            "issuingOffice" to str(v.issuingOffice),
            "nationalNumber" to str(v.nationalNumber),
            "nationality" to str(v.nationality),
            "bloodType" to str(v.bloodType),
            "licenceNumber" to str(v.licenceNumber),
            "categories" to str(v.categories),
            "address" to str(v.address),
            "allLines" to "[" + v.allLines.joinToString(",") { str(it) } + "]"
        )

        return obj(
            "verified" to f.verified.toString(),
            "mrz" to mrz,
            "mrzMatchesViz" to f.mrzMatchesViz.toString(),
            "licenceNumber" to str(f.licenceNumber),
            "nationalNumber" to str(f.nationalNumber),
            "viz" to viz
        )
    }

    fun back(cats: List<LicenceCategory>): String =
        "[" + cats.joinToString(",") {
            obj(
                "code" to str(it.code),
                "issueDate" to str(it.issueDate),
                "expiryDate" to str(it.expiryDate)
            )
        } + "]"

    private fun obj(vararg pairs: Pair<String, String>): String =
        "{" + pairs.joinToString(",") { "${str(it.first)}:${it.second}" } + "}"

    /** يهرّب النص حسب مواصفات JSON */
    private fun str(s: String): String {
        val sb = StringBuilder("\"")
        for (c in s) {
            when (c) {
                '"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                else -> if (c.code < 0x20) sb.append(String.format("\\u%04x", c.code)) else sb.append(c)
            }
        }
        return sb.append('"').toString()
    }
}
