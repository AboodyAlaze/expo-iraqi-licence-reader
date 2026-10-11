package expo.modules.iraqilicencereader.parser

/**
 * قراءة وجه البطاقة (Visual Inspection Zone).
 *
 * تحذير: هذي المنطقة ما فيها أرقام تحقق — على عكس الـ MRZ.
 * أي غلطة بالـ OCR تمر بصمت، فاعتبر نتائجها "اقتراح" يراجعه المستخدم.
 */
data class VizResult(
    val nameLatin: String = "",
    val nameArabic: String = "",
    val dateOfBirth: String = "",
    val dateOfIssue: String = "",
    val dateOfExpiry: String = "",
    val issuingOffice: String = "",
    val nationalNumber: String = "",
    val nationality: String = "",
    val bloodType: String = "",
    val licenceNumber: String = "",
    val categories: String = "",
    val address: String = "",
    val allLines: List<String> = emptyList()
) {
    /** مؤشر غنى القراءة — نستعمله لاختيار أفضل إطار */
    val richness: Int
        get() = listOf(
            nameLatin, nameArabic, dateOfBirth, dateOfIssue, dateOfExpiry,
            nationalNumber, bloodType, licenceNumber, categories
        ).count { it.isNotBlank() }
}

object VizParser {

    private val DATE = Regex("""(\d{2})\s*[./\-]\s*(\d{2})\s*[./\-]\s*(\d{4})""")
    private val LATIN_NAME = Regex("""^[A-Z][A-Z'\- ]{5,}$""")
    private val BLOOD = Regex("""\b(AB|A|B|O)\s?([+\-])""")
    private val NATIONAL = Regex("""\b\d{12,13}\b""")
    private val LICENCE = Regex("""\b([A-Z])\s?(\d{8})\b""")
    private val FIELD_TAG = Regex("""^\s*(\d{1,2}[a-d]?)\s*[.,]""")
    private val TAG_BEFORE = Regex("""(\d{1,2}[a-d]?)\s*[.,]\s*$""")
    // يشيل أرقام الحقول من بداية السطر — حتى المركّبة مثل "1,2." و "13b."
    private val STRIP_TAG = Regex("""^\s*(?:\d{1,2}[a-d]?\s*[.,]\s*)+""")
    private val CATEGORIES = Regex("""^\s*([A-D]\d?\+?(?:\s+[A-D]\d?\+?)*)\s*$""")

    private val HEADER_LATIN = listOf(
        "KURDISTAN", "MINISTRY", "INTERIOR", "DRIVING",
        "LICENCE", "LICENSE", "REGION", "REPUBLIC", "TRAFFIC"
    )

    private val HEADER_ARABIC = listOf(
        "إقليم", "كوردستان", "كۆمارى", "وزارة", "الداخلية", "وەزارەتى",
        "إجازة", "السياقة", "العراق", "عێراق", "جمهورية",
        "مۆڵەتی", "شۆفێری", "ناوخۆ", "مولەتى", "شوفێرى"
    )

    fun parse(rawText: String): VizResult {
        val lines = rawText.lines().map { it.trim() }.filter { it.isNotEmpty() }

        // نربط كل تاريخ برقم حقله: 3=ميلاد 4a=إصدار 4b=انتهاء
        val labelled = mutableMapOf<String, String>()
        val unlabelled = mutableListOf<String>()

        var nameLatin = ""
        var nameArabic = ""
        var blood = ""
        var office = ""
        var national = ""
        var licence = ""
        var nationality = ""
        var categories = ""
        val addressParts = mutableListOf<String>()

        for (line in lines) {
            val lineTag = FIELD_TAG.find(line)?.groupValues?.get(1)?.lowercase()
            val clean = line.replace(STRIP_TAG, "").trim()

            DATE.findAll(line).forEach { m ->
                val d = "${m.groupValues[1]}/${m.groupValues[2]}/${m.groupValues[3]}"
                val before = line.substring(0, m.range.first)
                val tag = TAG_BEFORE.find(before)?.groupValues?.get(1)?.lowercase() ?: lineTag

                when (tag) {
                    "3" -> labelled.putIfAbsent("3", d)
                    "4a" -> labelled.putIfAbsent("4a", d)
                    "4b" -> labelled.putIfAbsent("4b", d)
                    else -> if (d !in unlabelled) unlabelled.add(d)
                }
            }

            if (blood.isEmpty()) {
                BLOOD.find(line)?.let { blood = it.groupValues[1] + it.groupValues[2] }
            }

            if (nationality.isEmpty()) {
                when {
                    clean.contains("IRAQI", ignoreCase = true) -> nationality = "IRAQI"
                    clean.contains("عراقي") || clean.contains("عێراقی") -> nationality = "عراقي"
                }
            }

            if (office.isEmpty() && clean.contains("Traffic", ignoreCase = true)) office = clean

            if (nameLatin.isEmpty() && LATIN_NAME.matches(clean)) {
                if (HEADER_LATIN.none { clean.contains(it) }) nameLatin = clean
            }

            if (hasArabic(clean) && clean.none { it.isDigit() } && clean.length > 2) {
                if (HEADER_ARABIC.none { clean.contains(it) }) {
                    if (nameArabic.isEmpty()) nameArabic = clean else addressParts.add(clean)
                }
            }

            if (national.isEmpty()) NATIONAL.find(line)?.let { national = it.value }

            if (licence.isEmpty()) {
                LICENCE.find(line)?.let { licence = it.groupValues[1] + it.groupValues[2] }
            }

            if (categories.isEmpty()) {
                CATEGORIES.find(clean)?.let { m ->
                    val v = m.groupValues[1].trim()
                    if (v.length > 1 || v in listOf("A", "B", "C", "D")) categories = v
                }
            }
        }

        // الحقول المرقّمة لها الأولوية، والباقي بالترتيب الزمني
        val all = (labelled.values + unlabelled).distinct()
        val sorted = all.sortedBy { yearOf(it) }

        var dob = labelled["3"] ?: ""
        var issue = labelled["4a"] ?: ""
        var expiry = labelled["4b"] ?: ""

        if (dob.isEmpty() && sorted.isNotEmpty()) dob = sorted.first()

        val afterDob = sorted.filter { it != dob }
        if (expiry.isEmpty() && afterDob.isNotEmpty()) expiry = afterDob.last()
        if (issue.isEmpty() && afterDob.size >= 2) issue = afterDob[afterDob.size - 2]

        // الانتهاء لازم يكون بعد الإصدار
        if (issue.isNotEmpty() && expiry.isNotEmpty() && yearOf(issue) > yearOf(expiry)) {
            val t = issue; issue = expiry; expiry = t
        }

        return VizResult(
            nameLatin = nameLatin,
            nameArabic = nameArabic,
            dateOfBirth = dob,
            dateOfIssue = issue,
            dateOfExpiry = expiry,
            issuingOffice = office,
            nationalNumber = national,
            nationality = nationality,
            bloodType = blood,
            licenceNumber = licence,
            categories = categories,
            address = addressParts.joinToString("، "),
            allLines = lines
        )
    }

    private fun hasArabic(s: String) =
        s.any { it.code in 0x0600..0x06FF || it.code in 0x0750..0x077F }

    private fun yearOf(d: String) = d.takeLast(4).toIntOrNull() ?: 0
}
