package expo.modules.iraqilicencereader.parser

/** فئة واحدة من جدول ظهر الإجازة — لها تاريخ إصدار وانتهاء مستقل */
data class LicenceCategory(
    val code: String,
    val issueDate: String = "",
    val expiryDate: String = ""
)

object CategoryCatalog {
    /** ترتيب الصفوف كما يظهر بظهر البطاقة — أساس الاستنتاج الهندسي */
    val ORDER = listOf(
        "A1", "A", "B", "C1", "C", "D1", "D",
        "BE", "C1E", "CE", "D1E", "DE", "T"
    )
}

/**
 * يقرأ جدول الفئات من ظهر الإجازة.
 *
 * المشكلة الحاسمة: الـ OCR ما يقرأ الأكواد القصيرة (A, B, C) بشكل
 * موثوق — يقرأ A1 و D1 ويفوّت الباقي. فالاعتماد على "أقرب كود
 * مقروء" يفشل ويعطي فئة وحدة بدل أربعة.
 *
 * الحل: نستعمل الأكواد المقروءة كنقاط مرجعية، ونحسب ارتفاع الصف
 * الواحد بانحدار خطي على كل النقاط. بعدها نستنتج أي صف بالجدول
 * يقع فيه كل زوج تواريخ — حتى لو كوده ما انقرأ أبداً.
 *
 * وبما إن تاريخ الانتهاء غالباً موحّد لعدة صفوف، ما نستعمل
 * distinct داخل الصف — نميّز العمودين بالموقع الأفقي.
 */
object CategoryParser {

    private val SHORT_DATE = Regex("""(\d{2})\s*[./\-]\s*(\d{2})\s*[./\-]\s*(\d{2})\b""")
    private val FULL_DATE = Regex("""(\d{2})\s*[./\-]\s*(\d{2})\s*[./\-]\s*(\d{4})""")
    private val CODE_EXACT = Regex("""^\s*(A1|A|B|C1|C|D1|D|BE|C1E|CE|D1E|DE|T)\s*$""")
    private val CODE_ANY = Regex("""\b(A1|A|B|C1|C|D1|D|BE|C1E|CE|D1E|DE|T)\b""")

    private fun gap(a: Int, b: Int): Int = if (a > b) a - b else b - a

    /** الطريقة الدقيقة — تعتمد على الإحداثيات */
    fun parseBlocks(blocks: List<TextBlock>): List<LicenceCategory> {
        val codeBlocks = mutableListOf<Pair<TextBlock, String>>()
        val dateBlocks = mutableListOf<Pair<TextBlock, String>>()

        for (b in blocks) {
            val t = b.text.trim()

            val codeMatch = CODE_EXACT.find(t)
            if (codeMatch != null) {
                codeBlocks.add(b to codeMatch.groupValues[1])
                continue
            }

            val dates = extractDates(t)
            if (dates.size == 1) {
                dateBlocks.add(b to dates.first())
            } else if (dates.size >= 2) {
                dates.forEach { dateBlocks.add(b to it) }
            }
        }

        if (dateBlocks.isEmpty() || codeBlocks.size < 2) return emptyList()

        val rows = groupByRow(dateBlocks).filter { it.size >= 2 }
        if (rows.isEmpty()) return emptyList()

        // نقاط مرجعية: (رقم الصف بالجدول، الموقع العمودي)
        val anchors = codeBlocks.mapNotNull { (blk, code) ->
            val idx = CategoryCatalog.ORDER.indexOf(code)
            if (idx >= 0) idx to blk.centerY else null
        }
        if (anchors.size < 2) return emptyList()

        // انحدار خطي: y = rowHeight * index + originY
        val n = anchors.size.toDouble()
        val sumX = anchors.sumOf { it.first.toDouble() }
        val sumY = anchors.sumOf { it.second.toDouble() }
        val sumXY = anchors.sumOf { it.first.toDouble() * it.second.toDouble() }
        val sumXX = anchors.sumOf { it.first.toDouble() * it.first.toDouble() }

        val denom = n * sumXX - sumX * sumX
        if (denom > -0.0001 && denom < 0.0001) return emptyList()

        val rowHeight = (n * sumXY - sumX * sumY) / denom
        val originY = (sumY - rowHeight * sumX) / n

        // ارتفاع صف صغير أو سالب يعني قراءة فاسدة
        if (rowHeight < 4.0) return emptyList()

        val out = mutableListOf<LicenceCategory>()
        val usedRows = mutableSetOf<Int>()

        for (row in rows) {
            val byX = row.sortedBy { it.first.centerX }
            val first = byX.first().second
            val last = byX.last().second
            if (first == last) continue

            val issue = if (yearOf(first) <= yearOf(last)) first else last
            val expiry = if (yearOf(first) <= yearOf(last)) last else first

            val rowY = row.map { it.first.centerY.toDouble() }.average()
            val rowIndex = Math.round((rowY - originY) / rowHeight).toInt()

            if (rowIndex < 0 || rowIndex >= CategoryCatalog.ORDER.size) continue
            if (rowIndex in usedRows) continue

            // الاستنتاج لازم يكون قريب كفاية من مركز صف حقيقي
            val expectedY = originY + rowIndex * rowHeight
            if (gap(rowY.toInt(), expectedY.toInt()) > rowHeight * 0.5) continue

            usedRows.add(rowIndex)
            out.add(LicenceCategory(CategoryCatalog.ORDER[rowIndex], issue, expiry))
        }

        return out.sortedBy { CategoryCatalog.ORDER.indexOf(it.code) }
    }

    /** يجمع القطع اللي بنفس الارتفاع العمودي */
    private fun groupByRow(
        items: List<Pair<TextBlock, String>>
    ): List<List<Pair<TextBlock, String>>> {
        val sorted = items.sortedBy { it.first.centerY }
        val rows = mutableListOf<MutableList<Pair<TextBlock, String>>>()

        for (item in sorted) {
            val row = rows.lastOrNull()
            var belongs = false
            if (row != null) {
                val avgY = row.map { it.first.centerY.toDouble() }.average()
                val avgH = row.map { it.first.height.toDouble() }.average()
                val limit = (avgH * 0.5).toInt().coerceAtLeast(6)
                belongs = gap(item.first.centerY, avgY.toInt()) <= limit
            }
            if (belongs) row!!.add(item) else rows.add(mutableListOf(item))
        }
        return rows
    }

    /** طريقة احتياطية بالنص الخام — أقل دقة، فقط إذا الإحداثيات مو متاحة */
    fun parse(rawText: String): List<LicenceCategory> {
        val out = mutableListOf<LicenceCategory>()

        for (line in rawText.lines().map { it.trim() }.filter { it.isNotEmpty() }) {
            val dates = extractDates(line)
            if (dates.size < 2) continue

            val codes = CODE_ANY.findAll(line).map { it.groupValues[1] }.toList()
            val code = codes.maxByOrNull { it.length } ?: continue

            val s = dates.sortedBy { yearOf(it) }
            out.add(LicenceCategory(code, s.first(), s.last()))
        }

        return out
            .distinctBy { it.code }
            .sortedBy { c -> CategoryCatalog.ORDER.indexOf(c.code).takeIf { it >= 0 } ?: 99 }
    }

    /** يستخرج التواريخ ويوحّدها لصيغة DD/MM/YYYY — بدون حذف المكرر */
    private fun extractDates(line: String): List<String> {
        val out = mutableListOf<String>()

        FULL_DATE.findAll(line).forEach { m ->
            out.add("${m.groupValues[1]}/${m.groupValues[2]}/${m.groupValues[3]}")
        }
        SHORT_DATE.findAll(line).forEach { m ->
            val yy = m.groupValues[3].toIntOrNull() ?: return@forEach
            val year = if (yy < 70) 2000 + yy else 1900 + yy
            out.add("${m.groupValues[1]}/${m.groupValues[2]}/$year")
        }
        return out
    }

    private fun yearOf(d: String) = d.takeLast(4).toIntOrNull() ?: 0
}
