import Foundation

/// فئة واحدة من جدول ظهر الإجازة.
///
/// كل فئة لها تاريخ إصدار وانتهاء مستقل — ممكن تكون الدراجة
/// منتهية والسيارة سارية بنفس البطاقة.
struct LicenceCategory: Identifiable {
    let code: String
    var issueDate: String = ""
    var expiryDate: String = ""

    var id: String { code }

    var label: String { CategoryCatalog.labels[code] ?? "" }

    /// هل الفئة سارية حسب تاريخ اليوم؟
    var isValid: Bool {
        guard let exp = Self.parse(expiryDate) else { return true }
        let today = Calendar.current.dateComponents([.day, .month, .year], from: Date())
        guard let td = today.day, let tm = today.month, let ty = today.year else { return true }

        if exp.year != ty { return exp.year > ty }
        if exp.month != tm { return exp.month > tm }
        return exp.day >= td
    }

    private static func parse(_ s: String) -> (day: Int, month: Int, year: Int)? {
        let parts = s.split(separator: "/")
        guard parts.count == 3,
              let d = Int(parts[0]), let m = Int(parts[1]), let y = Int(parts[2])
        else { return nil }
        return (d, m, y)
    }
}

enum CategoryCatalog {

    /// ترتيب الصفوف كما يظهر بظهر البطاقة — أساس الاستنتاج الهندسي
    static let order = [
        "A1", "A", "B", "C1", "C", "D1", "D",
        "BE", "C1E", "CE", "D1E", "DE", "T"
    ]

    static let labels: [String: String] = [
        "A1": "دراجة صغيرة",
        "A": "دراجة نارية",
        "B": "سيارة خصوصي",
        "C1": "شاحنة خفيفة",
        "C": "شاحنة",
        "D1": "باص صغير",
        "D": "باص",
        "BE": "خصوصي مع مقطورة",
        "C1E": "شاحنة خفيفة مع مقطورة",
        "CE": "شاحنة مع مقطورة",
        "D1E": "باص صغير مع مقطورة",
        "DE": "باص مع مقطورة",
        "T": "ساحبة"
    ]
}

/// يقرأ جدول الفئات من ظهر الإجازة.
///
/// المشكلة الحاسمة: الـ OCR ما يقرأ الأكواد القصيرة (A, B, C)
/// بشكل موثوق — يقرأ A1 و D1 ويفوّت الباقي. فالاعتماد على
/// "أقرب كود مقروء" يفشل ويعطي فئة وحدة بدل أربعة.
///
/// الحل: نستعمل الأكواد المقروءة كنقاط مرجعية، ونحسب ارتفاع
/// الصف الواحد من المسافة بينها. بعدها نستنتج أي صف بالجدول
/// يقع فيه كل زوج تواريخ — حتى لو كوده ما انقرأ أبداً.
enum CategoryParser {

    private static let shortDate = "(\\d{2})\\s*[./\\-]\\s*(\\d{2})\\s*[./\\-]\\s*(\\d{2})\\b"
    private static let fullDate = "(\\d{2})\\s*[./\\-]\\s*(\\d{2})\\s*[./\\-]\\s*(\\d{4})"
    private static let codeExact = "^\\s*(A1|A|B|C1|C|D1|D|BE|C1E|CE|D1E|DE|T)\\s*$"
    private static let codeAny = "\\b(A1|A|B|C1|C|D1|D|BE|C1E|CE|D1E|DE|T)\\b"

    /// الطريقة الدقيقة — تعتمد على الإحداثيات
    static func parseBlocks(_ blocks: [TextBlock]) -> [LicenceCategory] {
        var codeBlocks: [(TextBlock, String)] = []
        var dateBlocks: [(TextBlock, String)] = []

        for b in blocks {
            let t = b.text.trimmingCharacters(in: .whitespaces)

            if let code = firstMatch(t, pattern: codeExact, group: 1) {
                codeBlocks.append((b, code))
                continue
            }

            let dates = extractDates(t)
            if dates.count == 1 {
                dateBlocks.append((b, dates[0]))
            } else if dates.count >= 2 {
                dates.forEach { dateBlocks.append((b, $0)) }
            }
        }

        guard !dateBlocks.isEmpty, codeBlocks.count >= 2 else { return [] }

        let rows = groupByRow(dateBlocks).filter { $0.count >= 2 }
        guard !rows.isEmpty else { return [] }

        // نقاط مرجعية: كل كود مقروء مع رقم صفه وموقعه
        let anchors: [(index: Int, y: Int)] = codeBlocks.compactMap { blk, code in
            guard let idx = CategoryCatalog.order.firstIndex(of: code) else { return nil }
            return (idx, blk.centerY)
        }.sorted { $0.y < $1.y }

        guard anchors.count >= 2 else { return [] }

        // انحدار خطي على كل النقاط المرجعية — أدق من متوسط
        // الأزواج المتجاورة، لأن قراءة كود واحدة خاطئة ما تخرّب
        // التقدير كله. y = slope * rowIndex + intercept
        let n = Double(anchors.count)
        let sumX = anchors.reduce(0.0) { $0 + Double($1.index) }
        let sumY = anchors.reduce(0.0) { $0 + Double($1.y) }
        let sumXY = anchors.reduce(0.0) { $0 + Double($1.index) * Double($1.y) }
        let sumXX = anchors.reduce(0.0) { $0 + Double($1.index) * Double($1.index) }

        let denom = n * sumXX - sumX * sumX
        guard abs(denom) > 0.0001 else { return [] }

        let rowHeight = (n * sumXY - sumX * sumY) / denom
        let originY = (sumY - rowHeight * sumX) / n

        // ارتفاع صف سالب أو صغير جداً يعني قراءة فاسدة
        guard rowHeight > 4 else { return [] }

        var out: [LicenceCategory] = []
        var usedRows = Set<Int>()

        for row in rows {
            let byX = row.sorted { $0.0.centerX < $1.0.centerX }
            guard let first = byX.first?.1, let last = byX.last?.1, first != last else { continue }

            let issue = yearOf(first) <= yearOf(last) ? first : last
            let expiry = yearOf(first) <= yearOf(last) ? last : first

            let rowY = Double(row.map { $0.0.centerY }.reduce(0, +)) / Double(row.count)

            // نستنتج رقم الصف من موقعه
            let rowIndex = Int((rowY - originY) / rowHeight + 0.5)

            guard rowIndex >= 0, rowIndex < CategoryCatalog.order.count else { continue }
            guard !usedRows.contains(rowIndex) else { continue }

            // نتحقق إن الاستنتاج قريب كفاية من مركز صف حقيقي
            let expectedY = originY + Double(rowIndex) * rowHeight
            guard abs(rowY - expectedY) <= rowHeight * 0.5 else { continue }

            usedRows.insert(rowIndex)
            out.append(
                LicenceCategory(
                    code: CategoryCatalog.order[rowIndex],
                    issueDate: issue,
                    expiryDate: expiry
                )
            )
        }

        return out.sorted {
            (CategoryCatalog.order.firstIndex(of: $0.code) ?? 99) <
            (CategoryCatalog.order.firstIndex(of: $1.code) ?? 99)
        }
    }

    /// يجمع القطع اللي بنفس الارتفاع العمودي
    private static func groupByRow(_ items: [(TextBlock, String)]) -> [[(TextBlock, String)]] {
        let sorted = items.sorted { $0.0.centerY < $1.0.centerY }
        var rows: [[(TextBlock, String)]] = []

        for item in sorted {
            if var last = rows.last {
                let avgY = Double(last.map { $0.0.centerY }.reduce(0, +)) / Double(last.count)
                let avgH = Double(last.map { $0.0.height }.reduce(0, +)) / Double(last.count)
                let limit = max(Int(avgH * 0.5), 6)

                if abs(item.0.centerY - Int(avgY)) <= limit {
                    last.append(item)
                    rows[rows.count - 1] = last
                    continue
                }
            }
            rows.append([item])
        }
        return rows
    }

    /// طريقة احتياطية بالنص الخام — أقل دقة
    static func parse(_ rawText: String) -> [LicenceCategory] {
        var out: [LicenceCategory] = []

        for line in rawText.components(separatedBy: .newlines) {
            let dates = extractDates(line)
            guard dates.count >= 2 else { continue }
            guard let code = allMatches(line, pattern: codeAny, group: 1)
                .max(by: { $0.count < $1.count }) else { continue }

            let s = dates.sorted { yearOf($0) < yearOf($1) }
            out.append(LicenceCategory(code: code, issueDate: s[0], expiryDate: s[s.count - 1]))
        }

        var seen = Set<String>()
        return out.filter { seen.insert($0.code).inserted }
            .sorted {
                (CategoryCatalog.order.firstIndex(of: $0.code) ?? 99) <
                (CategoryCatalog.order.firstIndex(of: $1.code) ?? 99)
            }
    }

    // MARK: أدوات

    static func extractDates(_ line: String) -> [String] {
        var out: [String] = []
        let ns = line as NSString

        if let re = try? NSRegularExpression(pattern: fullDate) {
            for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                let d = ns.substring(with: m.range(at: 1))
                let mo = ns.substring(with: m.range(at: 2))
                let y = ns.substring(with: m.range(at: 3))
                out.append("\(d)/\(mo)/\(y)")
            }
        }

        if let re = try? NSRegularExpression(pattern: shortDate) {
            for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                let d = ns.substring(with: m.range(at: 1))
                let mo = ns.substring(with: m.range(at: 2))
                guard let yy = Int(ns.substring(with: m.range(at: 3))) else { continue }
                let year = yy < 70 ? 2000 + yy : 1900 + yy
                out.append("\(d)/\(mo)/\(year)")
            }
        }

        return out
    }

    private static func firstMatch(_ s: String, pattern: String, group: Int) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length))
        else { return nil }
        return ns.substring(with: m.range(at: group))
    }

    private static func allMatches(_ s: String, pattern: String, group: Int) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: group)) }
    }

    private static func yearOf(_ d: String) -> Int {
        Int(d.suffix(4)) ?? 0
    }
}
