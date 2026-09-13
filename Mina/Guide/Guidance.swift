import Foundation

/// The age-by-age content behind the Guide tab, and the typical ranges the
/// Today screen quotes as "expect 7–10 a day". Plain data, in the spirit of AAP
/// guidance, with the stages laid end to end so every day of her first year
/// falls in exactly one.

// MARK: Values

/// Typical ranges for a stage, used both in the guide and as "expect" hints
/// on the Today screen.
struct Expectation {
    let feedsPerDay: ClosedRange<Int>
    let mlPerFeed: ClosedRange<Double>
    let wetDiapersPerDay: Int
    let sleepHours: ClosedRange<Double>

    func feedsText() -> String { "\(feedsPerDay.lowerBound)–\(feedsPerDay.upperBound) a day" }
    func perFeedText(unit: VolumeUnit) -> String {
        let low = VolumeUnit.trim(unit.display(ml: mlPerFeed.lowerBound).rounded())
        let high = VolumeUnit.trim(unit.display(ml: mlPerFeed.upperBound).rounded())
        return "\(low)–\(high) \(unit.symbol) each"
    }
    func wetText() -> String { "\(wetDiapersPerDay)+ wet" }
    func sleepText() -> String { "\(VolumeUnit.trim(sleepHours.lowerBound))–\(VolumeUnit.trim(sleepHours.upperBound))h" }
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
}

// MARK: The content

/// General newborn ranges in the spirit of AAP guidance. Not medical advice;
/// the pediatrician who has actually met the baby always wins.
enum Guidance {
    static func stage(forAgeDays days: Int) -> GuideStage {
        stages.first { $0.ageDays.contains(max(0, days)) } ?? stages[stages.count - 1]
    }

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
            id: "month-4", title: "Month 4", ageDays: 91...365,
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
    ]
}
