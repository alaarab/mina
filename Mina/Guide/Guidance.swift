import Foundation

/// The age-by-age content behind the Guide tab, and the typical ranges the
/// Today screen quotes as "expect 7–10 a day". Plain data, in the spirit of AAP
/// guidance, with the stages laid end to end so every day through toddlerhood
/// falls in exactly one.

// MARK: Values

/// Typical ranges for a stage, used both in the guide and as "expect" hints
/// on the Today screen.
struct Expectation {
    var feedsPerDay: ClosedRange<Int>? = nil
    var mlPerFeed: ClosedRange<Double>? = nil
    var wetDiapersPerDay: Int? = nil
    var sleepHours: ClosedRange<Double>? = nil

    func feedsText() -> String { feedsPerDay.map { "\($0.lowerBound)–\($0.upperBound) a day" } ?? "Follow her routine" }
    func perFeedText(unit: VolumeUnit) -> String {
        guard let mlPerFeed else { return "Follow her routine" }
        let low = VolumeUnit.trim(unit.display(ml: mlPerFeed.lowerBound).rounded())
        let high = VolumeUnit.trim(unit.display(ml: mlPerFeed.upperBound).rounded())
        return "\(low)–\(high) \(unit.symbol) each"
    }
    func wetText() -> String { wetDiapersPerDay.map { "\($0)+ wet" } ?? "Follow her routine" }
    func sleepText() -> String { sleepHours.map { "\(VolumeUnit.trim($0.lowerBound))–\(VolumeUnit.trim($0.upperBound))h" } ?? "Follow her routine" }
}

struct GuideStage: Identifiable {
    let id: String
    let title: String
    let ageDays: ClosedRange<Int>
    let headline: String
    let expectation: Expectation
    let feeding: [String]
    let diapers: [String]
    let sleep: [String]
    let growth: [String]
    let milestones: [String]
    let checkups: [String]
    let watchFor: [String]
    var startMonth: Int? = nil
}

// MARK: The content

/// Newborn ranges and sourced older-infant/toddler guidance. Not medical advice;
/// the pediatrician who has actually met the baby always wins.
enum Guidance {
    static func stage(forAgeDays days: Int) -> GuideStage {
        stages.first { $0.ageDays.contains(max(0, days)) } ?? stages[stages.count - 1]
    }

    /// Use calendar anniversaries for all six-month-and-older transitions.
    /// Day-only callers retain approximate ranges; app surfaces use the birthday.
    static func stage(birthDate: Date, on date: Date = .now, calendar: Calendar = .current) -> GuideStage {
        let birth = calendar.startOfDay(for: birthDate)
        let today = calendar.startOfDay(for: date)
        for stage in stages.reversed() {
            if let month = stage.startMonth,
               let boundary = calendar.date(byAdding: .month, value: month, to: birth), today >= boundary {
                return stage
            }
        }
        let days = calendar.dateComponents([.day], from: birth, to: today).day ?? 0
        return stage(forAgeDays: min(182, days))
    }

    static let sources: [(title: String, url: String)] = [
        ("CDC: food and feeding routines", "https://www.cdc.gov/infant-toddler-nutrition/foods-and-drinks/how-much-and-how-often-to-feed.html"),
        ("CDC: developmental checklists", "https://www.cdc.gov/act-early/milestones/index.html"),
        ("AASM: sleep duration", "https://aasm.org/recharge-with-sleep-pediatric-sleep-recommendations-promoting-optimal-health/"),
        ("AAP: well-child visits", "https://www.aap.org/periodicityschedule"),
        ("HealthyChildren: breathing trouble", "https://www.healthychildren.org/English/tips-tools/symptom-checker/IFrame/Pages/symptomviewer.aspx?symptom=Breathing+Trouble"),
    ]

    static let olderEveryday = [
        "Use Food to record meals, snacks and allergens; notes can record routines, toilet learning and questions for visits.",
        "Keep logging naps and nights, growth, medicine and family memories. Earlier entries stay in History.",
        "Read and play together. Use the CDC checklist for her age and discuss concerns or lost skills with her clinician.",
    ]

    static let olderWatchFor = ["Discuss feeding, growth or development concerns with her clinician. Report any skills she has lost."]

    static let olderCallTheDoctor = [
        "Trouble breathing, blue or grey lips, or being very hard to wake needs urgent medical help.",
        "Ask her clinician about fever, dehydration, persistent vomiting or blood in stool. Bring the log and describe changes from her usual pattern.",
    ]

    static let disclaimer = "These are general ranges drawn from pediatric guidance. Every baby is different; her pediatrician knows her, this app does not. Not medical advice."

    static let callTheDoctor: [String] = [
        "Rectal temperature of 100.4°F (38°C) or higher under 3 months old: call right away, day or night.",
        "Fewer than 6 wet diapers a day after day 5, dark urine, or a dry mouth.",
        "Won't wake for feeds, is hard to rouse, or refuses two feeds in a row.",
        "Breathing fast, grunting, flaring nostrils, or ribs pulling in with each breath.",
        "Blue or grey lips or face.",
        "Forceful or green vomiting, or blood in the stool.",
        "Yellow skin or eyes that deepens or spreads down to the belly and legs.",
        "White, red, or black stool after the first meconium days.",
        "Crying that can't be settled for hours, or a cry that sounds unlike her.",
    ]

    static let everyday: [String] = [
        "Tummy time from the first days: a few minutes at a time, several times a day, while she's awake and you're watching.",
        "Burp her midway through and after feeds. Hiccups and spit-up are normal.",
        "Sponge baths until the cord stump falls off, then 2–3 baths a week is plenty.",
        "Peeling skin, baby acne and tiny white bumps (milia) in the first weeks clear on their own.",
        "Back to sleep, every sleep, on a firm flat surface with nothing loose. Room-share, don't bed-share, for at least 6 months.",
        "Cluster feeding and fussy evenings are normal, especially weeks 2 through 8.",
        "You can't spoil a newborn. Hold her as much as you like.",
        "Take turns sleeping. A rested parent is part of her care too.",
    ]

    static let solids: [String] = [
        "Around 6 months, start when she can sit with support, control her head and bring food to her mouth; keep breast milk or formula as the main nutrition.",
        "Offer one food at a time at first. Mina can tag the nine common allergens so you can tell the clinician exactly what she tried and when.",
        "Use soft textures and upright, supervised feeding. Ask her clinician about allergen timing, especially with severe eczema or an existing food allergy.",
    ]

    static let stages: [GuideStage] = [
        GuideStage(
            id: "days-1-3", title: "Days 1–3", ageDays: 0...2,
            headline: "Tiny tummy, lots of sleep. Everything is small right now, and that's right.",
            expectation: Expectation(feedsPerDay: 8...12, mlPerFeed: 15...60, wetDiapersPerDay: 1, sleepHours: 16...18),
            feeding: [
                "Feed on demand, at least every 2–3 hours, 8–12 times a day. Her stomach holds about a teaspoon on day one and a shot glass by day three.",
                "Bottles: 0.5–2 oz (15–60 ml) per feed. Formula-fed babies usually take a little more each day.",
                "Nursing: 10–20 minutes a side is typical. Colostrum comes in tiny amounts and that is exactly right. Milk usually comes in around day 3–5.",
                "Wake her to feed if she's slept 3–4 hours, until she is back to her birth weight.",
            ],
            diapers: [
                "Day 1: at least 1 wet and 1 stool. Day 2: 2 wet. Day 3: 3 wet.",
                "First stools are meconium: black, sticky and tar-like. Normal.",
                "By day 3–4 stools turn green, then yellow.",
            ],
            sleep: [
                "16–18 hours a day, in 1–3 hour stretches around the clock.",
                "Always on her back, on a firm flat surface, with nothing loose in the bassinet.",
            ],
            growth: ["She'll lose up to 7–10% of her birth weight in the first days. That is expected."],
            milestones: [
                "Rooting and sucking reflexes, tight fists, startles at noise.",
                "Sees about 8–12 inches, roughly your face while feeding.",
            ],
            checkups: [
                "Hepatitis B vaccine, hearing screen and newborn blood screen happen before you leave the hospital.",
                "Pediatrician visit at 3–5 days old, or 1–2 days after discharge.",
            ],
            watchFor: [
                "Fewer wet diapers than her age in days (day 2 with only 1 wet).",
                "Yellow skin or eyes that seems to spread (jaundice).",
                "Too sleepy to wake for feeds, or not latching or taking a bottle.",
            ]
        ),
        GuideStage(
            id: "first-week", title: "First week", ageDays: 3...6,
            headline: "Milk is coming in and diapers pick up. Feeds are frequent and short.",
            expectation: Expectation(feedsPerDay: 8...12, mlPerFeed: 30...90, wetDiapersPerDay: 4, sleepHours: 16...18),
            feeding: [
                "8–12 feeds a day, every 2–3 hours. Cluster feeding in the evening is normal.",
                "Bottles: 1–3 oz (30–90 ml) per feed.",
                "Milk comes in around day 3–5: breasts feel fuller and you'll hear her swallowing.",
                "Keep waking her if she goes past 4 hours, until she's regained her birth weight.",
            ],
            diapers: [
                "Day 4: 4 wet. From day 5: 6 or more pale-yellow wet diapers a day.",
                "Stools turn mustard-yellow and seedy (breastfed) or tan and pastier (formula). 3–4 or more a day is typical.",
                "Pink or orange 'brick dust' in the diaper in the first days is urate crystals. Mention it if it lasts past day 4.",
            ],
            sleep: ["16–18 hours a day in short stretches. Day and night are the same to her for now."],
            growth: ["Weight loss should stop around day 5 and start turning around."],
            milestones: ["Turns toward your voice, calms when held, brief moments of eye contact."],
            checkups: ["First pediatrician visit: weight, jaundice check, feeding review. Bring this log."],
            watchFor: [
                "Fewer than 6 wet diapers after day 5.",
                "No stool in 24 hours during the first week.",
                "Fever of 100.4°F (38°C) or higher means a call, at this age always.",
            ]
        ),
        GuideStage(
            id: "week-2", title: "Week 2", ageDays: 7...13,
            headline: "Back toward birth weight. A growth spurt often lands around day 7–10.",
            expectation: Expectation(feedsPerDay: 8...12, mlPerFeed: 60...90, wetDiapersPerDay: 6, sleepHours: 15...17),
            feeding: [
                "Still 8–12 feeds a day, roughly every 2–3 hours, 2–3 oz (60–90 ml) per bottle.",
                "Formula rule of thumb: about 2.5 oz per pound of body weight per day.",
                "A growth spurt around 7–10 days: she seems hungrier for a day or two, then settles.",
            ],
            diapers: ["6+ wet and 3–4+ dirty a day. Breastfed stools are loose and yellow; that's not diarrhea."],
            sleep: ["15–17 hours in 2–4 hour stretches. The longest stretch, often at night, is 3–4 hours."],
            growth: ["Back to birth weight by 10–14 days, then gaining about 5–7 oz (150–200 g) a week."],
            milestones: ["Lifts her head briefly in tummy time, follows a face slowly, hands mostly fisted."],
            checkups: [
                "A weight check around 2 weeks if the doctor asked for one.",
                "The cord stump usually falls off between 1 and 3 weeks.",
            ],
            watchFor: [
                "Not back to birth weight by 2 weeks.",
                "Redness, swelling or a smell around the cord stump.",
            ]
        ),
        GuideStage(
            id: "weeks-3-4", title: "Weeks 3–4", ageDays: 14...27,
            headline: "Bigger feeds, slightly longer gaps, and the fussy evenings start to peak.",
            expectation: Expectation(feedsPerDay: 7...10, mlPerFeed: 90...120, wetDiapersPerDay: 6, sleepHours: 15...17),
            feeding: [
                "7–10 feeds a day, 3–4 oz (90–120 ml) per bottle, every 3–4 hours. Around 24 oz a day total for formula.",
                "Once she's above birth weight and gaining, let her take a longer stretch at night if she wants it.",
                "Growth spurts at 2–3 weeks and again around 6 weeks.",
            ],
            diapers: ["6+ wet a day. Stool frequency starts to vary; some breastfed babies go once a day, some after every feed."],
            sleep: [
                "15–17 hours. Wake windows are about 45–60 minutes.",
                "Night stretches of 3–4 hours are common. Longer is a bonus, not a problem, once weight gain is steady.",
                "Fussy evenings build from now through 6 weeks. It's a phase, not a verdict on your parenting.",
            ],
            growth: ["Gaining 5–7 oz a week and about an inch a month."],
            milestones: [
                "Holds her head up briefly, moves it side to side in tummy time, focuses on faces.",
                "First real smiles show up around 4–6 weeks.",
            ],
            checkups: ["1-month visit: weight, length, head size, and the second hepatitis B dose (sometimes at 2 months instead)."],
            watchFor: [
                "Crying that can't be soothed for hours every day: talk to the doctor about colic and reflux.",
                "Spit-up is normal. Forceful vomiting or green vomit is not.",
            ]
        ),
        GuideStage(
            id: "month-2", title: "Month 2", ageDays: 28...55,
            headline: "Smiles arrive, nights stretch out a bit, and the 2-month shots come.",
            expectation: Expectation(feedsPerDay: 6...8, mlPerFeed: 120...150, wetDiapersPerDay: 6, sleepHours: 14...17),
            feeding: [
                "6–8 feeds a day, 4–5 oz (120–150 ml) per bottle, every 3–4 hours. About 24–32 oz a day total.",
                "She may take more per feed and go longer between them.",
                "Vitamin D drops (400 IU a day) for breastfed babies, if the doctor recommends them.",
            ],
            diapers: ["5–6+ wet a day. Breastfed babies may stool less often now, even every few days, and that's fine if it's soft."],
            sleep: [
                "14–17 hours. Wake windows 60–90 minutes. Night stretches of 4–6 hours are possible.",
                "Day/night confusion usually sorts itself out around 6–8 weeks.",
            ],
            growth: ["About 1.5–2 lb gained per month in these early months."],
            milestones: [
                "Social smiles around 6–8 weeks, cooing, follows objects with her eyes, holds her head up in tummy time, hands starting to open.",
                "Crying peaks around 6 weeks, then eases.",
            ],
            checkups: ["2-month visit: first big round of vaccines (DTaP, IPV, Hib, PCV, rotavirus, HepB). Expect a fussy, sleepy day after."],
            watchFor: [
                "Not smiling or reacting to your voice by 2 months.",
                "Mild fever after vaccines is common, but 100.4°F or higher under 3 months still means a call.",
            ]
        ),
        GuideStage(
            id: "month-3", title: "Month 3", ageDays: 56...90,
            headline: "Steadier head, real laughs, and longer nights for many babies.",
            expectation: Expectation(feedsPerDay: 5...7, mlPerFeed: 120...180, wetDiapersPerDay: 5, sleepHours: 14...16),
            feeding: [
                "5–7 feeds a day, 4–6 oz (120–180 ml) each. Around 24–32 oz a day; more than 32 oz is worth mentioning to the doctor.",
                "A growth spurt around 3 months is common.",
            ],
            diapers: ["5–6 wet a day. Stools vary widely; soft is what matters."],
            sleep: [
                "14–16 hours. Wake windows 60–90 minutes. Many babies do a 5–6 hour stretch at night now.",
                "Naps consolidate slowly; 4–5 naps a day is still typical.",
            ],
            growth: ["Weight gain slows a little, to about 4–5 oz a week."],
            milestones: ["Holds her head steady, pushes up on her forearms, bats at toys, brings her hands together, laughs and squeals, knows you."],
            checkups: ["No routine visit at 3 months. The next one is at 4 months."],
            watchFor: [
                "Not holding her head up or not tracking objects by 3 months.",
                "Drooling and chewing on hands is normal and not necessarily teething.",
            ]
        ),
        GuideStage(
            id: "month-4", title: "Months 4–5", ageDays: 91...182,
            headline: "Rolling, grabbing, babbling. Sleep may wobble for a few weeks; that's development, not regression.",
            expectation: Expectation(feedsPerDay: 5...6, mlPerFeed: 150...210, wetDiapersPerDay: 5, sleepHours: 12...16),
            feeding: [
                "5–6 feeds a day, 5–7 oz (150–210 ml). Still milk only; solids usually wait until about 6 months.",
            ],
            diapers: ["5+ wet a day."],
            sleep: ["12–16 hours. Wake windows 1.5–2 hours. The '4-month sleep regression' is a real shift in how she sleeps; more night waking for a few weeks is common."],
            growth: ["Roughly double her birth weight by 4–6 months."],
            milestones: ["Rolls tummy to back, grabs and holds toys, babbles, laughs, may push down with her legs when held standing."],
            checkups: ["4-month visit: second round of the 2-month vaccines."],
            watchFor: ["Not reaching for things, not making sounds, or a body that feels very stiff or very floppy."]
        ),
        GuideStage(
            id: "months-6-8", title: "Months 6–8", ageDays: 183...273,
            headline: "Food joins the log. Milk feeds and family routines still matter.",
            expectation: Expectation(sleepHours: 12...16),
            feeding: ["Breast milk or infant formula remains the main nutrition through the first year. Record foods, textures and allergens alongside milk feeds.", "Watch hunger and fullness cues. Agree on feeding amounts with her clinician; Mina no longer sets a milk-volume target from weight."],
            diapers: ["Record changes from her usual wet and stool pattern; food can change stools."],
            sleep: ["The AASM sleep range for 4–12 months is 12–16 hours in 24 hours, including naps. Log nights and naps together.", "Follow her sleep cues and logged routine; Mina stops its newborn nap-window estimate at six months."],
            growth: ["Keep measurements dated so you can review the pattern with her clinician."],
            milestones: ["By 6 months: takes turns making sounds with you.", "By 6 months: reaches for a wanted toy.", "By 6 months: supports sitting by leaning on her hands."],
            checkups: ["Review the 6-month visit and upcoming 9-month developmental screening in Visits & vaccines."],
            watchFor: olderWatchFor, startMonth: 6
        ),
        GuideStage(
            id: "months-9-11", title: "Months 9–11", ageDays: 274...364,
            headline: "More foods and more ways to play. Keep the details both parents need.",
            expectation: Expectation(sleepHours: 12...16),
            feeding: ["Keep breast milk or infant formula alongside foods through the first year. Use Food for meals and snacks, and notes for reactions or questions."],
            diapers: ["Compare with her own usual pattern rather than a newborn diaper quota."],
            sleep: ["12–16 hours per 24 hours, including naps, is the AASM range. Use the log to share her current routine."],
            growth: ["Measurements and dated notes help with the 9- and 12-month visits."],
            milestones: ["By 9 months: looks toward you when called by name.", "By 9 months: sits with no support.", "By 9 months: moves an object between her hands."],
            checkups: ["9-month developmental screening; plan the 12-month visit with her clinician."],
            watchFor: olderWatchFor, startMonth: 9
        ),
        GuideStage(
            id: "months-12-17", title: "Months 12–17", ageDays: 365...547,
            headline: "The first birthday changes the routine, not the family log.",
            expectation: Expectation(sleepHours: 11...14),
            feeding: ["Regular meals and snacks help build a routine. Food logs can capture what she tried and common allergens.", "From 12 months, discuss milk and other drinks with her clinician. Nursing can stay in the log; Mina sets no automatic milk-feed quota."],
            diapers: ["Keep diaper logging when useful; record toilet learning in notes without a daily diaper target."],
            sleep: ["The AASM range for ages 1–2 is 11–14 hours per 24 hours, including naps."],
            growth: ["Keep growth measurements and review them with her clinician. Mina's WHO girls' percentile tables end at 24 months."],
            milestones: ["By 1 year: waves goodbye.", "By 1 year: pulls herself up to stand.", "By 1 year: walks while holding furniture."],
            checkups: ["12- and 15-month visits; use Visits & vaccines to record completed care."],
            watchFor: olderWatchFor, startMonth: 12
        ),
        GuideStage(
            id: "months-18-23", title: "Months 18–23", ageDays: 548...729,
            headline: "Keep track of meals, sleep and the moments you want to remember.",
            expectation: Expectation(sleepHours: 11...14),
            feeding: ["Offer meals and snacks at regular times, with textures appropriate for her. Record foods and questions rather than judging the day by bottle totals."],
            diapers: ["Diapers remain available. Notes can record toilet routines or changes to discuss at a visit."],
            sleep: ["11–14 hours per 24 hours, including naps, is the AASM range for ages 1–2."],
            growth: ["Review her measurements over time with her clinician rather than treating a percentile as a diagnosis."],
            milestones: ["Save new words, play and movement in dated milestone notes. Use the CDC 18-month checklist with her clinician."],
            checkups: ["18-month developmental and autism screening; plan the 2-year visit."],
            watchFor: olderWatchFor, startMonth: 18
        ),
        GuideStage(
            id: "months-24-29", title: "Months 24–29", ageDays: 730...912,
            headline: "Two years of history, with room for today's routines.",
            expectation: Expectation(sleepHours: 11...14),
            feeding: ["Keep meals and snacks in Food, allergens attached to the entry, and any feeding concerns in notes."],
            diapers: ["Use diapers or notes as useful during toilet learning; Mina has no diaper quota for toddlers."],
            sleep: ["11–14 hours per 24 hours, including naps, is the AASM range for two-year-olds."],
            growth: ["Growth logging continues. Mina does not calculate percentiles beyond its 24-month tables; take measurements to her clinician."],
            milestones: ["By 2 years: combines at least two words.", "By 2 years: kicks a ball.", "By 2 years: eats using a spoon."],
            checkups: ["2-year visit and autism screening; 30-month developmental screening is next."],
            watchFor: olderWatchFor, startMonth: 24
        ),
        GuideStage(
            id: "months-30-35", title: "Months 30–35", ageDays: 913...1095,
            headline: "Meals, naps, words and play: a shared record through toddlerhood.",
            expectation: Expectation(sleepHours: 11...14),
            feeding: ["Use Food for meals and snacks. Use notes to share routines and questions between caregivers."],
            diapers: ["Record toilet learning in notes, with diapers still available whenever needed."],
            sleep: ["11–14 hours per 24 hours, including naps, is the AASM range until the third birthday."],
            growth: ["Save measurements for visits; percentiles are outside Mina's current table range."],
            milestones: ["By 30 months: follows an instruction with two steps.", "By 30 months: uses objects for pretend play.", "By 30 months: jumps with both feet leaving the ground."],
            checkups: ["30-month developmental screening, then the 3-year well-child visit."],
            watchFor: olderWatchFor, startMonth: 30
        ),
        GuideStage(
            id: "beyond-guide", title: "3 years & beyond", ageDays: 1096...Int.max,
            headline: "Her log keeps going. Age-specific guidance here covers birth to the third birthday.",
            expectation: Expectation(),
            feeding: ["Food, bottles and nursing remain available. Set any personal targets with her clinician."],
            diapers: ["Diapers and routine notes remain available."],
            sleep: ["Keep logging sleep and reviewing trends with her clinician; Mina sets no age-specific target here."],
            growth: ["Growth measurements stay in History; Mina's percentile tables stop at 24 months."],
            milestones: [], checkups: ["The 3-year visit is in Visits & vaccines. Plan further visits with her clinician."],
            watchFor: olderWatchFor, startMonth: 36
        ),
    ]
}

/// Calendar-based ages shared by app, widgets and the Foundation test harness.
enum ChildAge {
    static func days(birthDate: Date, on date: Date = .now, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: birthDate), to: calendar.startOfDay(for: date)).day ?? 0
    }

    static func months(birthDate: Date, on date: Date, calendar: Calendar = .current) -> Double? {
        let birth = calendar.startOfDay(for: birthDate), today = calendar.startOfDay(for: date)
        guard today >= birth else { return nil }
        var whole = calendar.dateComponents([.month], from: birth, to: today).month ?? 0
        while let next = calendar.date(byAdding: .month, value: whole + 1, to: birth), next <= today { whole += 1 }
        guard let lower = calendar.date(byAdding: .month, value: whole, to: birth),
              let upper = calendar.date(byAdding: .month, value: whole + 1, to: birth) else { return nil }
        return Double(whole) + today.timeIntervalSince(lower) / upper.timeIntervalSince(lower)
    }

    /// "5 days old", "3 weeks, 2 days old", "4 months, 1 week old".
    static func description(birthDate: Date?, on date: Date = .now, calendar: Calendar = .current) -> String {
        guard let birthDate else { return "" }
        let days = Self.days(birthDate: birthDate, on: date, calendar: calendar)
        if days < 0 { return "Arriving soon" }
        if days == 0 { return "Born today" }
        if days < 7 { return Format.count(days, "day") + " old" }
        if days < 91 {
            let weeks = days / 7, rest = days % 7
            var text = Format.count(weeks, "week")
            if rest > 0 { text += ", " + Format.count(rest, "day") }
            return text + " old"
        }
        let birth = calendar.startOfDay(for: birthDate), today = calendar.startOfDay(for: date)
        let months = Int(Self.months(birthDate: birthDate, on: date, calendar: calendar) ?? 0)
        if months >= 12 {
            let years = months / 12, rest = months % 12
            return Format.count(years, "year") + (rest > 0 ? ", " + Format.count(rest, "month") : "") + " old"
        }
        let anchor = calendar.date(byAdding: .month, value: months, to: birth) ?? birth
        let weeks = (calendar.dateComponents([.day], from: anchor, to: today).day ?? 0) / 7
        var text = Format.count(months, "month")
        if weeks > 0 { text += ", " + Format.count(weeks, "week") }
        return text + " old"
    }
}
