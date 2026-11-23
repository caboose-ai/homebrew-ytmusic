import Foundation

/// Decides whether a track is safe to show in a public Slack status.
/// A flagged track still plays and still feeds Now Playing; only the Slack
/// text falls back to a generic line, so coworkers see "Listening to music"
/// instead of an explicit title. Edit the lists below to taste.
enum StatusFilter {
    static let genericStatus = "Listening to music"

    static func isClean(_ text: String) -> Bool {
        let normalized = normalize(text)
        if blockedSubstrings.contains(where: { normalized.contains($0) }) {
            return false
        }
        let tokens = normalized.split(whereSeparator: { !$0.isLetter }).map(String.init)
        return !tokens.contains(where: { blockedWords.contains($0) })
    }

    // Lowercase, strip accents, and fold common look-alikes so "Sh1t" and
    // "F@ck" are caught. Mapped digits become letters before tokenizing.
    private static func normalize(_ text: String) -> String {
        let folded = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
        let lookalikes: [Character: Character] = [
            "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "$": "s", "@": "a", "!": "i",
        ]
        return String(folded.map { lookalikes[$0] ?? $0 })
    }

    // Matched anywhere, even inside longer words. Only terms that are explicit
    // in any context belong here; a rare false positive (Scunthorpe) just means
    // a generic status, not a blocked track.
    private static let blockedSubstrings: [String] = [
        "fuck", "shit", "bitch", "cunt", "whore", "slut", "pussy", "dildo",
        "blowjob", "handjob", "rimjob", "cocksuck", "deepthroat", "gangbang",
        "bukkake", "hentai", "jizz", "wank", "twat", "masturbat", "orgasm",
        "porn", "strapon", "incest", "molest", "pedophil", "paedophil",
        "nigg", "fagg", "tranny", "retard",
        // Masked and alternate spellings. "@" folds to "a" and "*" survives
        // normalization, so these cover censored titles like "F**k You".
        "f**k", "f*ck", "fu*k", "s**t", "sh*t", "b*tch", "c*nt", "p*ssy",
        "fack", "fuk", "fuq", "phuck", "biatch",
    ]

    // Matched only as whole words, so "Class", "Cumbia", "Dickens", "Cockpit"
    // and "grape" pass while the bare words are caught.
    private static let blockedWords: Set<String> = [
        "ass", "anal", "cock", "cum", "dick", "tit", "tits", "titties",
        "sex", "sexy", "hoe", "hoes", "thot", "milf", "kink", "kinky",
        "bdsm", "orgy", "nude", "nudes", "horny", "smut", "piss", "prick",
        "boner", "schlong", "clit", "coochie", "rape", "raped", "rapes",
        "rapist", "wap",
    ]
}
