import Foundation

struct Milestone: Codable, Identifiable, Hashable {
    let thresholdML: Double
    let icon: String
    let name: String
    let blurb: String

    var id: String { name }
}

enum Milestones {
    /// Cumulative water, in millilitres. Kept in step with MILESTONES in
    /// plugin/engine/water.py.
    static let all: [Milestone] = [
        Milestone(thresholdML: 1,             icon: "💧", name: "First Drop",          blurb: "One millilitre. It begins."),
        Milestone(thresholdML: 10,            icon: "🧪", name: "Eye Dropper",         blurb: "10 mL. A pipette's worth of thinking."),
        Milestone(thresholdML: 50,            icon: "☕", name: "Espresso Shot",       blurb: "50 mL. Enough to pull a single shot."),
        Milestone(thresholdML: 250,           icon: "🥃", name: "A Glass of Water",    blurb: "250 mL. You could have just had a drink."),
        Milestone(thresholdML: 500,           icon: "🥤", name: "The Bottle",          blurb: "500 mL. One standard bottle of water."),
        Milestone(thresholdML: 1_000,         icon: "💦", name: "Litre Club",          blurb: "1 L. Officially measurable in litres now."),
        Milestone(thresholdML: 3_785,         icon: "🪣", name: "Gallon Guzzler",      blurb: "3.79 L. One US gallon."),
        Milestone(thresholdML: 6_000,         icon: "🚽", name: "Toilet Flush",        blurb: "6 L. One modern low-flow flush."),
        Milestone(thresholdML: 15_000,        icon: "🍽", name: "Dishwasher Cycle",    blurb: "15 L. A full eco cycle."),
        Milestone(thresholdML: 50_000,        icon: "🚿", name: "Five-Minute Shower",  blurb: "50 L. One shower, start to finish."),
        Milestone(thresholdML: 65_000,        icon: "🧺", name: "Laundry Load",        blurb: "65 L. One wash of a full machine."),
        Milestone(thresholdML: 150_000,       icon: "🛁", name: "Full Bathtub",        blurb: "150 L. Filled to the overflow."),
        Milestone(thresholdML: 310_000,       icon: "🏠", name: "One Person, One Day", blurb: "310 L. Average household use, per person, per day."),
        Milestone(thresholdML: 1_000_000,     icon: "🧊", name: "Cubic Metre",         blurb: "1,000 L. One tonne of water."),
        Milestone(thresholdML: 2_700_000,     icon: "👕", name: "Cotton T-Shirt",      blurb: "2,700 L. What it takes to grow and make one shirt."),
        Milestone(thresholdML: 7_600_000,     icon: "👖", name: "One Pair of Jeans",   blurb: "7,600 L. Denim is thirsty."),
        Milestone(thresholdML: 15_000_000,    icon: "🐄", name: "One Kilo of Beef",    blurb: "15,000 L. The heavyweight of food footprints."),
        Milestone(thresholdML: 50_000_000,    icon: "🚛", name: "Tanker Truck",        blurb: "50,000 L. A full road tanker."),
        Milestone(thresholdML: 100_000_000,   icon: "🏖", name: "Backyard Pool",       blurb: "100,000 L. Above ground, vinyl liner, questionable filter."),
        Milestone(thresholdML: 600_000_000,   icon: "🏢", name: "Water Tower",         blurb: "600,000 L. A small town's buffer."),
        Milestone(thresholdML: 2_500_000_000, icon: "🏊", name: "Olympic Pool",        blurb: "2,500,000 L. Fifty metres of regret."),
        Milestone(thresholdML: 25_000_000_000, icon: "🌊", name: "Reservoir",          blurb: "25,000,000 L. At this point, please stop."),
    ]

    static func unlocked(at total: Double) -> [Milestone] { all.filter { total >= $0.thresholdML } }
    static func next(after total: Double) -> Milestone? { all.first { total < $0.thresholdML } }
}

enum Format {
    /// The same ladder the Python side uses, so the menu bar, the DMG's app and
    /// `/water` never disagree about what to call a number.
    static func ml(_ value: Double) -> String {
        if value < 1 { return String(format: "%.2f mL", value) }
        if value < 10 { return String(format: "%.1f mL", value) }
        if value < 1000 { return String(format: "%.0f mL", value.rounded()) }
        let litres = value / 1000
        if litres < 10 { return String(format: "%.2f L", litres) }
        if litres < 1000 { return String(format: "%.1f L", litres) }
        if litres < 1_000_000 { return String(format: "%.1f kL", litres / 1000) }
        // Not "ML": next to "500 mL" a capital M is a coin-flip for the reader.
        var millions = String(format: "%.1f", litres / 1_000_000)
        if millions.hasSuffix(".0") { millions.removeLast(2) }
        return "\(millions) million L"
    }

    static func count(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
