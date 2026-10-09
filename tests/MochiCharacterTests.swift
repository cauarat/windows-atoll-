// Characters: the rules that decide what a Mochi's face does.
//
// Compiled against EyeShape.swift + MochiCharacter.swift alone, with no app, so
// these run in a second and can be trusted. Run with scripts/test-mochi-character.sh.

import Foundation

@main
enum MochiCharacterTests {

    static var failures = 0

    static func check(_ condition: Bool, _ what: String) {
        if condition {
            print("  \u{2713} \(what)")
        } else {
            print("  \u{2717} \(what)")
            failures += 1
        }
    }

    static func main() {
        // `--dump` prints the catalogue for the TypeScript side to compare
        // against, so the two hand-kept ports cannot drift apart unnoticed.
        if CommandLine.arguments.contains("--dump") {
            for preset in CharacterCatalog.presets {
                print("\(preset.id)\t\(preset.name)\t\(preset.character.storageString)")
            }
            return
        }



        /// Every shape that is not `pill` or `wide` — the bot expressing something.
        let expressive: [EyeShape] = [.dot, .line, .flat, .happy, .closed, .spiral,
                                      .heart, .star, .tired, .wink, .cup]
        let allShapes: [EyeShape] = expressive + [.pill, .wide]

        // MARK: – Classic Mochi is untouched

        print("\nClassic Mochi")

        let classic = MochiCharacter()
        check(classic.isClassic, "no accessory and no eyes is the classic character")
        for shape in allShapes {
            check(classic.resolve(shape) == .plain(shape),
                  "classic passes \(shape.rawValue) straight through")
        }

        // MARK: – Eyes that ARE the eye

        print("\nReplacing eyes step aside for an expression")

        for eye in MochiEye.allCases where !eye.isSpanning {
            let character = MochiCharacter(accessory: nil, eye: eye)

            check(character.resolve(.pill) == .character(eye, wide: false),
                  "\(eye.rawValue) replaces the neutral pill")
            check(character.resolve(.wide) == .character(eye, wide: true),
                  "\(eye.rawValue) replaces wide, and keeps approval's enlargement")

            for shape in expressive {
                check(character.resolve(shape) == .plain(shape),
                      "\(eye.rawValue) leaves \(shape.rawValue) alone")
            }
        }

        // The one that would be missed: a character whose eyes happen to be dots must
        // still show the *surprised* dot, not silently swallow it. Same drawing, but
        // the rule has to route it through the plain path so `es` and the emote timing
        // apply as usual.
        let dotty = MochiCharacter(accessory: nil, eye: .dot)
        check(dotty.resolve(.dot) == .plain(.dot),
              "a dot-eyed character still routes the surprised dot through the plain path")

        // MARK: – Eyes that are WORN

        print("\nWorn eyes stay on through everything")

        for eye in MochiEye.allCases where eye.isSpanning {
            let character = MochiCharacter(accessory: nil, eye: eye)
            for shape in allShapes {
                check(character.resolve(shape) == .behindLens(shape, eye),
                      "\(eye.rawValue) survives \(shape.rawValue), with it drawn as the glint")
            }
        }

        // The whole reason the two kinds exist. Stated as its own assertion so that if
        // somebody later "simplifies" resolve() into one rule, this is what fails.
        let shaded = MochiCharacter(accessory: nil, eye: .shades)
        check(shaded.resolve(.closed) == .behindLens(.closed, .shades),
              "a bot in sunglasses does not take them off to fall asleep")
        check(shaded.resolve(.spiral) == .behindLens(.spiral, .shades),
              "a bot in sunglasses does not take them off when it gets dizzy")
        check(MochiCharacter(accessory: nil, eye: .visor).resolve(.happy) == .behindLens(.happy, .visor),
              "a visor stays on while the bot is pleased with itself")

        check(MochiEye.visor.isSpanning && MochiEye.shades.isSpanning,
              "visor and shades are the worn ones")
        check(!MochiEye.dot.isSpanning && !MochiEye.glossy.isSpanning
              && !MochiEye.pixel.isSpanning && !MochiEye.sleepy.isSpanning,
              "dot, glossy, pixel and sleepy are the grown ones")

        // MARK: – Which shapes count as neutral

        print("\nNeutral shapes")

        check(EyeShape.pill.isNeutral && EyeShape.wide.isNeutral, "pill and wide are neutral")
        for shape in expressive {
            check(!shape.isNeutral, "\(shape.rawValue) is not neutral")
        }

        // MARK: – The eighteen

        print("\nThe preset grid")

        let presets = CharacterCatalog.presets
        check(presets.count == 18, "eighteen presets, one per tile of the grid")

        let ids = Set(presets.map(\.id))
        let names = Set(presets.map(\.name))
        check(ids.count == 18, "every preset id is distinct")
        check(names.count == 18, "every preset name is distinct")

        let pairs = presets.map(\.character)
        check(Set(pairs.map(\.storageString)).count == 18, "no two presets are the same character")

        for accessory in MochiAccessory.allCases {
            check(pairs.contains { $0.accessory == accessory },
                  "\(accessory.rawValue) appears in the grid")
        }
        for eye in MochiEye.allCases {
            check(pairs.contains { $0.eye == eye }, "\(eye.rawValue) appears in the grid")
        }
        check(pairs.contains { $0.accessory == nil }, "the grid offers a bare head too")

        for preset in presets {
            check(CharacterCatalog.preset(matching: preset.character)?.id == preset.id,
                  "\(preset.name) is found again from its character")
        }
        check(CharacterCatalog.preset(matching: MochiCharacter(accessory: .crown, eye: .sleepy)) == nil,
              "a combination nobody named matches no preset")

        // MARK: – Which accessories go behind the body

        print("\nDraw order")

        check(MochiAccessory.catEars.isBehind && MochiAccessory.horns.isBehind
              && MochiAccessory.antenna.isBehind && MochiAccessory.sprout.isBehind,
              "what grows out of the head is drawn behind it")
        check(!MochiAccessory.crown.isBehind && !MochiAccessory.bow.isBehind
              && !MochiAccessory.beret.isBehind && !MochiAccessory.sparkles.isBehind,
              "what is worn on top is drawn in front")

        // MARK: – Storage

        print("\nStorage round-trip")

        for preset in presets {
            let text = preset.character.storageString
            check(MochiCharacter(storage: text) == preset.character,
                  "\(preset.name) survives \"\(text)\"")
        }
        check(MochiCharacter(storage: "-:-") == MochiCharacter(), "\"-:-\" is the classic character")

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for preset in presets {
            guard let data = try? encoder.encode(preset.character),
                  let back = try? decoder.decode(MochiCharacter.self, from: data) else {
                check(false, "\(preset.name) encodes and decodes")
                continue
            }
            check(back == preset.character, "\(preset.name) survives JSON")
        }

        // A settings file from a later build, or edited by hand. Nothing here may throw:
        // the island has to come up looking like Mochi rather than not at all.
        print("\nRubbish in settings")

        for junk in ["", "-", ":", "wizardHat:lasers", "crown", "crown:", ":glossy",
                     "crown:glossy:extra", "::", "  :  "] {
            let parsed = MochiCharacter(storage: junk)
            let accessoryOK = parsed.accessory == nil || MochiAccessory.allCases.contains(parsed.accessory!)
            let eyeOK = parsed.eye == nil || MochiEye.allCases.contains(parsed.eye!)
            check(accessoryOK && eyeOK, "\"\(junk)\" parses to something drawable")
        }
        check(MochiCharacter(storage: "wizardHat:lasers").isClassic,
              "a character this build has never heard of falls back to classic")
        check(MochiCharacter(storage: "crown:lasers") == MochiCharacter(accessory: .crown, eye: nil),
              "an unknown half is dropped and the known half kept")

        // MARK: – Result

        print("")
        if failures == 0 {
            print("All Mochi character tests passed.")
        } else {
            print("\(failures) failed.")
            exit(1)
        }

    }
}
