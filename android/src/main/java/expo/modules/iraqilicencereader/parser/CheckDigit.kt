package expo.modules.iraqilicencereader.parser

/**
 * خوارزمية رقم التحقق من معيار ICAO 9303 (أوزان 7-3-1).
 * إجازة السياقة العراقية تستعملها رغم إن تركيبة الـ MRZ مالتها غير قياسية.
 */
object CheckDigit {

    private val WEIGHTS = intArrayOf(7, 3, 1)

    fun compute(input: String): Char? {
        var sum = 0
        for ((i, c) in input.withIndex()) {
            val v = when (c) {
                in '0'..'9' -> c - '0'
                in 'A'..'Z' -> c - 'A' + 10
                '<' -> 0
                else -> return null
            }
            sum += v * WEIGHTS[i % 3]
        }
        return '0' + (sum % 10)
    }

    fun verify(body: String, expected: Char): Boolean = compute(body) == expected
}
