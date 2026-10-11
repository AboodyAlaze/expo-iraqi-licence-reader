package expo.modules.iraqilicencereader.parser

/**
 * قطعة نص مع موقعها الحقيقي على الصورة.
 * إحداثيات الـ OCR أدق بكثير من ترتيب النص الخام مع الجداول.
 */
data class TextBlock(
    val text: String,
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int
) {
    val centerY: Int get() = (top + bottom) / 2
    val centerX: Int get() = (left + right) / 2
    val height: Int get() = bottom - top
}
