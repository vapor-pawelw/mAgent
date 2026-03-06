import Foundation

enum NameGenerator {

    static let pokemonNames = [
        // Generation 1 – original selection
        "bulbasaur", "charmander", "squirtle", "butterfree", "beedrill",
        "pidgeot", "pikachu", "sandslash", "nidoqueen", "nidoking",
        "clefable", "ninetales", "wigglytuff", "golbat", "vileplume",
        "parasect", "venomoth", "dugtrio", "persian", "golduck",
        "primeape", "arcanine", "poliwrath", "alakazam", "machamp",
        "victreebel", "tentacruel", "golem", "rapidash", "slowbro",
        "magneton", "dodrio", "dewgong", "muk", "cloyster", "gengar",
        "hypno", "kingler", "electrode", "exeggutor", "marowak",
        "hitmonlee", "hitmonchan", "lickitung", "rhydon", "chansey",
        "tangela", "kangaskhan", "horsea", "seadra", "staryu",
        "mrmime", "scyther", "jynx", "electabuzz", "magmar",
        "pinsir", "tauros", "lapras", "ditto", "eevee",
        "vaporeon", "jolteon", "flareon", "porygon", "omanyte",
        "omastar", "kabuto", "kabutops", "aerodactyl", "snorlax",
        "articuno", "zapdos", "moltres", "dratini", "dragonair",
        "dragonite", "mewtwo", "mew",
        // Generation 2 – original selection
        "chikorita", "cyndaquil", "totodile", "meganium", "typhlosion",
        "feraligatr",
        // Generation 1 – additional
        "ivysaur", "venusaur", "charmeleon", "charizard", "wartortle",
        "blastoise", "caterpie", "metapod", "weedle", "kakuna",
        "pidgey", "pidgeotto", "rattata", "raticate", "spearow",
        "fearow", "ekans", "arbok", "raichu", "sandshrew",
        "nidorina", "clefairy", "vulpix", "jigglypuff", "zubat",
        "oddish", "gloom", "paras", "venonat", "diglett",
        "meowth", "psyduck", "mankey", "growlithe", "poliwag",
        "poliwhirl", "abra", "kadabra", "machop", "machoke",
        "bellsprout", "weepinbell", "tentacool", "geodude", "graveler",
        "ponyta", "slowpoke", "magnemite", "farfetchd", "doduo",
        "seel", "grimer", "shellder", "gastly", "haunter",
        "onix", "drowzee", "krabby", "voltorb", "exeggcute",
        "cubone", "koffing", "weezing", "rhyhorn", "goldeen",
        "seaking", "starmie", "magikarp", "gyarados",
        // Generation 2 – additional
        "bayleef", "quilava", "croconaw", "sentret", "furret",
        "hoothoot", "noctowl", "ledyba", "ledian", "spinarak",
        "ariados", "crobat", "chinchou", "lanturn", "pichu",
        "cleffa", "igglybuff", "togepi", "togetic", "xatu",
        "mareep", "flaaffy", "ampharos", "bellossom", "marill",
        "azumarill", "sudowoodo", "politoed", "hoppip", "skiploom",
        "jumpluff", "aipom", "sunkern", "sunflora", "yanma",
        "wooper", "quagsire", "espeon", "umbreon", "murkrow",
        "slowking", "misdreavus", "unown", "wobbuffet", "girafarig",
        "pineco", "forretress", "dunsparce", "gligar", "steelix",
        "snubbull", "granbull", "houndour", "qwilfish", "scizor", "shuckle",
        "heracross", "sneasel", "teddiursa", "ursaring", "slugma",
        "magcargo", "swinub", "piloswine", "corsola", "remoraid",
        "octillery", "delibird", "mantine", "skarmory",
        "houndoom", "kingdra", "phanpy", "donphan", "stantler",
        "smeargle",
        "tyrogue", "hitmontop", "smoochum", "elekid", "magby",
        "miltank", "blissey", "raikou", "entei", "suicune",
        "larvitar", "pupitar", "tyranitar", "lugia", "hooh",
        "celebi", "natu",
        // Generation 3
        // (skipped: latias — 1 letter from latios)
        "treecko", "grovyle", "sceptile", "torchic", "combusken",
        "blaziken", "mudkip", "marshtomp", "swampert", "poochyena",
        "mightyena", "zigzagoon", "linoone", "wurmple", "silcoon",
        "beautifly", "cascoon", "dustox", "lotad", "lombre",
        "ludicolo", "seedot", "nuzleaf", "shiftry", "taillow",
        "swellow", "wingull", "pelipper", "ralts", "kirlia",
        "gardevoir", "surskit", "masquerain", "shroomish", "breloom",
        "slakoth", "vigoroth", "slaking", "nincada", "ninjask",
        "shedinja", "whismur", "loudred", "exploud", "makuhita",
        "hariyama", "azurill", "nosepass", "skitty", "delcatty",
        "sableye", "mawile", "aron", "lairon", "aggron",
        "meditite", "medicham", "electrike", "manectric", "plusle",
        "minun", "volbeat", "illumise", "roselia", "gulpin",
        "swalot", "carvanha", "sharpedo", "wailmer", "wailord",
        "numel", "camerupt", "torkoal", "spoink", "grumpig",
        "spinda", "trapinch", "vibrava", "flygon", "cacnea",
        "cacturne", "swablu", "altaria", "zangoose", "seviper",
        "lunatone", "solrock", "barboach", "whiscash", "corphish",
        "crawdaunt", "baltoy", "claydol", "lileep", "cradily",
        "anorith", "armaldo", "feebas", "milotic", "castform",
        "kecleon", "shuppet", "banette", "duskull", "dusclops",
        "tropius", "chimecho", "absol", "wynaut", "snorunt",
        "glalie", "spheal", "sealeo", "walrein", "clamperl",
        "huntail", "gorebyss", "relicanth", "luvdisc", "bagon",
        "shelgon", "salamence", "beldum", "metang", "metagross",
        "regirock", "regice", "registeel", "latios", "kyogre",
        "groudon", "rayquaza", "jirachi", "deoxys",
        // Generation 4
        "turtwig", "grotle", "torterra", "chimchar", "monferno",
        "infernape", "piplup", "prinplup", "empoleon", "starly",
        "staravia", "staraptor", "bidoof", "bibarel", "kricketot",
        "kricketune", "shinx", "luxio", "luxray", "budew",
        "roserade", "cranidos",
    ]

    // Legacy word lists kept only for isAutoGenerated() backward compatibility.
    private static let legacyAdjectives = [
        "swift", "bright", "calm", "dark", "eager", "fair", "glad", "hazy",
        "keen", "lush", "mild", "neat", "odd", "pale", "quick", "rare",
        "sharp", "tall", "vast", "warm", "bold", "crisp", "deep", "fine",
        "gold", "high", "iron", "jade", "kind", "lean", "moss", "nova",
        "amber", "ashen", "azure", "clear", "dense", "fleet", "fresh", "grand",
        "green", "grey", "hardy", "light", "lone", "lucid", "noble", "plush",
        "prime", "pure", "quiet", "rough", "rust", "sage", "sleek", "slim",
        "soft", "stout", "terse", "true", "twin", "vivid", "wild", "wry",
    ]

    private static let legacyNouns = [
        "falcon", "brook", "cedar", "delta", "ember", "frost", "grove", "haven",
        "inlet", "jewel", "knoll", "larch", "maple", "nexus", "orbit", "pearl",
        "quill", "ridge", "shore", "thorn", "umbra", "vault", "whale", "xenon",
        "birch", "coral", "dusk", "fern", "gale", "heron", "ivory", "junco",
        "alder", "aspen", "bloom", "briar", "cliff", "crane", "creek", "crest",
        "drift", "finch", "flame", "flint", "forge", "glen", "heath", "ledge",
        "lotus", "lumen", "marsh", "opal", "pine", "plume", "raven", "reef",
        "robin", "slate", "spark", "spire", "stone", "trail", "vale", "wren",
    ]

    /// Returns the Pokemon name at `counter % pokemonNames.count`.
    static func generate(counter: Int) -> String {
        let index = counter % pokemonNames.count
        return pokemonNames[index]
    }

    /// Returns `true` when `name` matches an auto-generated pattern:
    /// - A Pokemon name (e.g. "pikachu")
    /// - A Pokemon name with numeric suffix (e.g. "pikachu-2")
    /// - Legacy "adjective-noun" or "adjective-noun-N" format
    static func isAutoGenerated(_ name: String) -> Bool {
        let parts = name.split(separator: "-").map(String.init)

        // Single-part: bare Pokemon name
        if parts.count == 1 {
            return pokemonNames.contains(parts[0])
        }

        // Two parts: could be "pokemon-N" (new) or "adjective-noun" (legacy)
        if parts.count == 2 {
            if pokemonNames.contains(parts[0]), Int(parts[1]) != nil {
                return true
            }
            if legacyAdjectives.contains(parts[0]), legacyNouns.contains(parts[1]) {
                return true
            }
            return false
        }

        // Three parts: legacy "adjective-noun-N"
        if parts.count == 3 {
            if legacyAdjectives.contains(parts[0]), legacyNouns.contains(parts[1]), Int(parts[2]) != nil {
                return true
            }
            return false
        }

        return false
    }
}
