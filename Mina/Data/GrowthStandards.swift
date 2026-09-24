import Foundation

/// WHO Child Growth Standards for girls, birth to five years. Mina's language
/// and current audience are girl-specific; the UI names that standard plainly.
/// LMS source workbooks:
/// https://www.who.int/tools/child-growth-standards/standards/weight-for-age
/// https://www.who.int/toolkits/child-growth-standards/standards/length-height-for-age
/// https://www.who.int/tools/child-growth-standards/standards/head-circumference-for-age
enum GrowthStandards {
    enum MeasureKind: String, CaseIterable {
        case weight = "Weight"
        case length = "Length"
        case head = "Head"
    }

    struct Result: Identifiable, Equatable {
        let kind: MeasureKind
        let percentile: Double
        var id: MeasureKind { kind }
        var label: String { "\(kind.rawValue) \(ordinal(percentile)) percentile" }
    }

    private struct LMS {
        let l: Double
        let m: Double
        let s: Double
    }

    static func results(for entry: LogEntry, birthDate: Date?, calendar: Calendar = .current) -> [Result] {
        guard let birthDate, let measuredAt = entry.startedAt else { return [] }
        let days = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: birthDate), to: calendar.startOfDay(for: measuredAt)).day ?? 0)
        let months = Double(days) / 30.4375
        var output: [Result] = []
        if entry.weightGrams > 0, let p = percentile(value: entry.weightGrams / 1000, ageMonths: months, table: weight) {
            output.append(.init(kind: .weight, percentile: p))
        }
        if entry.lengthCM > 0, let p = percentile(value: entry.lengthCM, ageMonths: months, table: length) {
            output.append(.init(kind: .length, percentile: p))
        }
        if entry.headCM > 0, let p = percentile(value: entry.headCM, ageMonths: months, table: head) {
            output.append(.init(kind: .head, percentile: p))
        }
        return output
    }

    static func percentile(value: Double, ageMonths: Double, kind: MeasureKind) -> Double? {
        percentile(value: value, ageMonths: ageMonths, table: kind == .weight ? weight : kind == .length ? length : head)
    }

    private static func percentile(value: Double, ageMonths: Double, table: [LMS]) -> Double? {
        guard value > 0, ageMonths >= 0, ageMonths <= Double(table.count - 1) else { return nil }
        let lower = min(Int(ageMonths.rounded(.down)), table.count - 1)
        let upper = min(lower + 1, table.count - 1)
        let fraction = ageMonths - Double(lower)
        let a = table[lower], b = table[upper]
        let l = a.l + (b.l - a.l) * fraction
        let m = a.m + (b.m - a.m) * fraction
        let s = a.s + (b.s - a.s) * fraction
        let z = abs(l) < 0.000_001 ? log(value / m) / s : (pow(value / m, l) - 1) / (l * s)
        return min(99.9, max(0.1, normalCDF(z) * 100))
    }

    /// Abramowitz-Stegun normal CDF approximation; error is below 0.00008,
    /// much smaller than the precision displayed to a parent.
    private static func normalCDF(_ z: Double) -> Double {
        let x = abs(z)
        let t = 1 / (1 + 0.2316419 * x)
        let density = 0.3989422804 * exp(-x * x / 2)
        let tail = density * t * (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))))
        return z >= 0 ? 1 - tail : tail
    }

    static func ordinal(_ percentile: Double) -> String {
        if percentile < 1 { return "<1st" }
        if percentile > 99 { return ">99th" }
        let value = Int(percentile.rounded())
        let tens = value % 100
        let suffix = (11...13).contains(tens) ? "th" : value % 10 == 1 ? "st" : value % 10 == 2 ? "nd" : value % 10 == 3 ? "rd" : "th"
        return "\(value)\(suffix)"
    }

    // Monthly LMS values copied from WHO's official girls' workbooks. Weight
    // and head cover 0...60 months; recumbent length covers 0...24 months.
    private static let weight: [LMS] = [
        .init(l: 0.3809, m: 3.2322, s: 0.14171), .init(l: 0.1714, m: 4.1873, s: 0.13724),
        .init(l: 0.0962, m: 5.1282, s: 0.13), .init(l: 0.0402, m: 5.8458, s: 0.12619),
        .init(l: -0.005, m: 6.4237, s: 0.12402), .init(l: -0.043, m: 6.8985, s: 0.12274),
        .init(l: -0.0756, m: 7.297, s: 0.12204), .init(l: -0.1039, m: 7.6422, s: 0.12178),
        .init(l: -0.1288, m: 7.9487, s: 0.12181), .init(l: -0.1507, m: 8.2254, s: 0.12199),
        .init(l: -0.17, m: 8.48, s: 0.12223), .init(l: -0.1872, m: 8.7192, s: 0.12247),
        .init(l: -0.2024, m: 8.9481, s: 0.12268), .init(l: -0.2158, m: 9.1699, s: 0.12283),
        .init(l: -0.2278, m: 9.387, s: 0.12294), .init(l: -0.2384, m: 9.6008, s: 0.12299),
        .init(l: -0.2478, m: 9.8124, s: 0.12303), .init(l: -0.2562, m: 10.023, s: 0.12306),
        .init(l: -0.2637, m: 10.232, s: 0.12309), .init(l: -0.2703, m: 10.439, s: 0.12315),
        .init(l: -0.2762, m: 10.646, s: 0.12323), .init(l: -0.2815, m: 10.853, s: 0.12335),
        .init(l: -0.2862, m: 11.061, s: 0.1235), .init(l: -0.2903, m: 11.269, s: 0.12369),
        .init(l: -0.2941, m: 11.477, s: 0.1239), .init(l: -0.2975, m: 11.686, s: 0.12414),
        .init(l: -0.3005, m: 11.895, s: 0.12441), .init(l: -0.3032, m: 12.101, s: 0.12472),
        .init(l: -0.3057, m: 12.306, s: 0.12506), .init(l: -0.308, m: 12.507, s: 0.12545),
        .init(l: -0.3101, m: 12.706, s: 0.12587), .init(l: -0.312, m: 12.901, s: 0.12633),
        .init(l: -0.3138, m: 13.093, s: 0.12683), .init(l: -0.3155, m: 13.284, s: 0.12737),
        .init(l: -0.3171, m: 13.473, s: 0.12794), .init(l: -0.3186, m: 13.662, s: 0.12855),
        .init(l: -0.3201, m: 13.85, s: 0.12919), .init(l: -0.3216, m: 14.039, s: 0.12988),
        .init(l: -0.323, m: 14.226, s: 0.13059), .init(l: -0.3243, m: 14.414, s: 0.13135),
        .init(l: -0.3257, m: 14.601, s: 0.13213), .init(l: -0.327, m: 14.787, s: 0.13293),
        .init(l: -0.3283, m: 14.973, s: 0.13376), .init(l: -0.3296, m: 15.157, s: 0.1346),
        .init(l: -0.3309, m: 15.341, s: 0.13545), .init(l: -0.3322, m: 15.524, s: 0.1363),
        .init(l: -0.3335, m: 15.706, s: 0.13716), .init(l: -0.3348, m: 15.888, s: 0.138),
        .init(l: -0.3361, m: 16.07, s: 0.13884), .init(l: -0.3374, m: 16.251, s: 0.13968),
        .init(l: -0.3387, m: 16.432, s: 0.14051), .init(l: -0.34, m: 16.613, s: 0.14132),
        .init(l: -0.3414, m: 16.794, s: 0.14213), .init(l: -0.3427, m: 16.975, s: 0.14293),
        .init(l: -0.344, m: 17.155, s: 0.14371), .init(l: -0.3453, m: 17.335, s: 0.14448),
        .init(l: -0.3466, m: 17.514, s: 0.14525), .init(l: -0.3479, m: 17.692, s: 0.146),
        .init(l: -0.3492, m: 17.869, s: 0.14675), .init(l: -0.3505, m: 18.044, s: 0.14748),
        .init(l: -0.3518, m: 18.219, s: 0.14821),
    ]

    private static let length: [LMS] = [
        .init(l: 1, m: 49.148, s: 0.0379), .init(l: 1, m: 53.687, s: 0.0364),
        .init(l: 1, m: 57.067, s: 0.03568), .init(l: 1, m: 59.803, s: 0.0352),
        .init(l: 1, m: 62.09, s: 0.03486), .init(l: 1, m: 64.03, s: 0.03463),
        .init(l: 1, m: 65.731, s: 0.03448), .init(l: 1, m: 67.287, s: 0.03441),
        .init(l: 1, m: 68.75, s: 0.0344), .init(l: 1, m: 70.144, s: 0.03444),
        .init(l: 1, m: 71.482, s: 0.03452), .init(l: 1, m: 72.771, s: 0.03464),
        .init(l: 1, m: 74.015, s: 0.03479), .init(l: 1, m: 75.218, s: 0.03496),
        .init(l: 1, m: 76.382, s: 0.03514), .init(l: 1, m: 77.51, s: 0.03534),
        .init(l: 1, m: 78.606, s: 0.03555), .init(l: 1, m: 79.671, s: 0.03576),
        .init(l: 1, m: 80.708, s: 0.03598), .init(l: 1, m: 81.718, s: 0.0362),
        .init(l: 1, m: 82.704, s: 0.03643), .init(l: 1, m: 83.665, s: 0.03666),
        .init(l: 1, m: 84.604, s: 0.03688), .init(l: 1, m: 85.52, s: 0.03711),
        .init(l: 1, m: 86.415, s: 0.03734),
    ]

    private static let head: [LMS] = [
        .init(l: 1, m: 33.879, s: 0.03496), .init(l: 1, m: 36.546, s: 0.0321),
        .init(l: 1, m: 38.252, s: 0.03168), .init(l: 1, m: 39.533, s: 0.0314),
        .init(l: 1, m: 40.582, s: 0.03119), .init(l: 1, m: 41.459, s: 0.03102),
        .init(l: 1, m: 42.2, s: 0.03087), .init(l: 1, m: 42.829, s: 0.03075),
        .init(l: 1, m: 43.367, s: 0.03063), .init(l: 1, m: 43.83, s: 0.03053),
        .init(l: 1, m: 44.232, s: 0.03044), .init(l: 1, m: 44.584, s: 0.03035),
        .init(l: 1, m: 44.897, s: 0.03027), .init(l: 1, m: 45.175, s: 0.03019),
        .init(l: 1, m: 45.426, s: 0.03012), .init(l: 1, m: 45.655, s: 0.03006),
        .init(l: 1, m: 45.865, s: 0.02999), .init(l: 1, m: 46.06, s: 0.02993),
        .init(l: 1, m: 46.242, s: 0.02987), .init(l: 1, m: 46.415, s: 0.02982),
        .init(l: 1, m: 46.58, s: 0.02977), .init(l: 1, m: 46.738, s: 0.02972),
        .init(l: 1, m: 46.891, s: 0.02967), .init(l: 1, m: 47.039, s: 0.02962),
        .init(l: 1, m: 47.182, s: 0.02957), .init(l: 1, m: 47.32, s: 0.02953),
        .init(l: 1, m: 47.454, s: 0.02949), .init(l: 1, m: 47.582, s: 0.02945),
        .init(l: 1, m: 47.705, s: 0.02941), .init(l: 1, m: 47.822, s: 0.02937),
        .init(l: 1, m: 47.934, s: 0.02933), .init(l: 1, m: 48.041, s: 0.02929),
        .init(l: 1, m: 48.143, s: 0.02926), .init(l: 1, m: 48.241, s: 0.02922),
        .init(l: 1, m: 48.334, s: 0.02919), .init(l: 1, m: 48.424, s: 0.02915),
        .init(l: 1, m: 48.51, s: 0.02912), .init(l: 1, m: 48.593, s: 0.02909),
        .init(l: 1, m: 48.672, s: 0.02906), .init(l: 1, m: 48.749, s: 0.02903),
        .init(l: 1, m: 48.823, s: 0.029), .init(l: 1, m: 48.894, s: 0.02897),
        .init(l: 1, m: 48.963, s: 0.02894), .init(l: 1, m: 49.029, s: 0.02891),
        .init(l: 1, m: 49.094, s: 0.02888), .init(l: 1, m: 49.156, s: 0.02886),
        .init(l: 1, m: 49.216, s: 0.02883), .init(l: 1, m: 49.275, s: 0.0288),
        .init(l: 1, m: 49.332, s: 0.02878), .init(l: 1, m: 49.388, s: 0.02875),
        .init(l: 1, m: 49.442, s: 0.02873), .init(l: 1, m: 49.495, s: 0.0287),
        .init(l: 1, m: 49.546, s: 0.02868), .init(l: 1, m: 49.597, s: 0.02865),
        .init(l: 1, m: 49.646, s: 0.02863), .init(l: 1, m: 49.695, s: 0.02861),
        .init(l: 1, m: 49.742, s: 0.02859), .init(l: 1, m: 49.788, s: 0.02856),
        .init(l: 1, m: 49.834, s: 0.02854), .init(l: 1, m: 49.879, s: 0.02852),
        .init(l: 1, m: 49.923, s: 0.0285),
    ]
}
