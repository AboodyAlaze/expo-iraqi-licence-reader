import CoreGraphics

/// قطعة نص مع موقعها الحقيقي على الصورة.
///
/// Vision يعطي إحداثيات لكل سطر، وهي أدق بكثير من ترتيب النص
/// الخام — خصوصاً مع الجداول اللي أعمدتها تنقرأ منفصلة.
struct TextBlock {
    let text: String
    let left: Int
    let top: Int
    let right: Int
    let bottom: Int

    var centerY: Int { (top + bottom) / 2 }
    var centerX: Int { (left + right) / 2 }
    var height: Int { bottom - top }

    /// هل هذي القطعة بنفس صف القطعة الثانية؟
    func sameRow(_ other: TextBlock, tolerance: Double = 0.5) -> Bool {
        let limit = max(Int(Double(height + other.height) / 2 * tolerance), 6)
        return abs(centerY - other.centerY) <= limit
    }
}
