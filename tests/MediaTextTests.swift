// MediaText — the title and artist cleaners, and the dump the Windows twin is
// compared against (scripts/test-media-text.sh).

import Foundation

/// Titles and artists the way players and YouTube actually send them, plus the
/// edges: nothing left after a cut, unbalanced brackets, spaces, non-ASCII.
@main
struct MediaTextTests {
    static let titles = [
        "Bohemian Rhapsody - Remastered 2011",
        "Song - 2011 Remaster (Live)",
        "Shape of You (Acoustic) [Official Video]",
        "Song [Live] (Remix)",
        "Title (feat. Someone)",
        "A - B - C",
        "(Intro)",
        "[Only brackets]",
        "Weird ) case",
        "Unbalanced (open",
        "Ends with ) (",
        "  spaced out  ",
        "Ünïcödé — dash (x)",
        "Vintage Christmas Songs 50s 60s 70s 🎧 Crosby, Sinatra, Nat King Cole, Fitzgerald",
        "Nested (a (b))",
        " - leading dash",
        "",
    ]
    static let artists = [
        "Drake feat. Rihanna",
        "Drake ft. Future",
        "Calvin Harris FEAT. Dua Lipa",
        "Someone Ft. Else",
        "feat. Nobody",
        " ft. Lead",
        "Plain Artist",
        "Featuring Someone",
        "Silent Christmas",
        "",
    ]

    nonisolated(unsafe) static var failures = 0

    static func check(_ got: String, _ want: String, _ what: String) {
        if got == want {
            print("  ✓ \(what)")
        } else {
            print("  ✗ \(what): got \"\(got)\", want \"\(want)\"")
            failures += 1
        }
    }

    static func main() {
        if CommandLine.arguments.contains("--dump") {
            for t in titles { print("title\t\(t)\t\(MediaText.shortTitle(t))") }
            for a in artists { print("artist\t\(a)\t\(MediaText.shortArtist(a))") }
            return
        }
        print("MediaText")
        check(MediaText.shortTitle("Bohemian Rhapsody - Remastered 2011"), "Bohemian Rhapsody", "cut at the first dash")
        check(MediaText.shortTitle("Shape of You (Acoustic) [Official Video]"), "Shape of You", "every trailing group goes")
        check(MediaText.shortTitle("(Intro)"), "(Intro)", "a title that is only a group stays")
        check(MediaText.shortTitle(""), "", "nothing stays nothing")
        check(MediaText.shortArtist("Drake feat. Rihanna"), "Drake", "feat. goes")
        check(MediaText.shortArtist("Calvin Harris FEAT. Dua Lipa"), "Calvin Harris", "in any case")
        check(MediaText.shortArtist("feat. Nobody"), "feat. Nobody", "no leading space, no cut")

        if failures > 0 {
            print("\(failures) failed")
            exit(1)
        }
        print("all passed")
    }
}
