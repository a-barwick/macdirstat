import Foundation

enum Format {
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f
    }()

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.doesRelativeDateFormatting = true
        return f
    }()

    static func bytes(_ n: Int64) -> String { byteFormatter.string(fromByteCount: n) }
    static func count(_ n: Int) -> String { numberFormatter.string(from: NSNumber(value: n)) ?? "\(n)" }

    static func percent(_ part: Int64, of whole: Int64) -> String {
        guard whole > 0 else { return "—" }
        let p = Double(part) / Double(whole) * 100
        if p >= 99.95 { return "100%" }
        if p < 0.1 { return p == 0 ? "0%" : "<0.1%" }
        return String(format: "%.1f%%", p)
    }

    static func date(_ seconds: Int) -> String {
        guard seconds > 0 else { return "—" }
        return dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }

    /// Paths under the home folder as `~/…`: shorter, and keeps usernames out of screenshots.
    static func path(_ p: String) -> String { (p as NSString).abbreviatingWithTildeInPath }

    static func duration(_ t: TimeInterval) -> String {
        t < 10 ? String(format: "%.1fs", t) : "\(Int(t.rounded()))s"
    }
}

/// Whimsy department.
enum Whimsy {
    static let scanVerbs = [
        "Rummaging", "Spelunking", "Tallying", "Pondering", "Burrowing", "Sifting",
        "Excavating", "Cataloguing", "Measuring", "Noodling", "Moseying", "Percolating",
        "Unfurling", "Combobulating", "Foraging", "Doodling", "Surveying", "Mapping",
        "Wrangling", "Tiptoeing", "Unpacking", "Leafing through",
    ]

    /// A friendly real-world yardstick for a pile of bytes.
    static func comparison(for bytes: Int64, seed: Int) -> String {
        let b = Double(bytes)
        guard b > 0 else { return "Light as a feather." }
        let options: [(Double, String, String)] = [
            (280, "tweet", "tweets"),
            (2_000, "page of plain text", "pages of plain text"),
            (75_000, "email", "emails"),
            (350_000, "emoji-laden group chat", "emoji-laden group chats"),
            (1_474_560, "floppy disk", "floppy disks"),
            (3_200_000, "copy of War and Peace", "copies of War and Peace"),
            (4_000_000, "MP3 song", "MP3 songs"),
            (3_500_000, "phone photo", "phone photos"),
            (700_000_000, "burned CD", "burned CDs"),
            (4_700_000_000, "DVD", "DVDs"),
            (3_000_000_000, "hour of HD video", "hours of HD video"),
            (25_000_000_000, "Blu-ray", "Blu-rays"),
        ]
        let sensible = options.filter { b / $0.0 >= 1 && b / $0.0 < 20_000 }
        guard !sensible.isEmpty else { return "About \(Int(b)) bytes of pure potential." }
        let pick = sensible[abs(seed) % sensible.count]
        let n = b / pick.0
        let nice = n < 10 ? String(format: "%.1f", n) : Format.count(Int(n.rounded()))
        return "≈ \(nice) \(n < 1.05 ? pick.1 : pick.2)"
    }
}
