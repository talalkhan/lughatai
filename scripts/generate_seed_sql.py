#!/usr/bin/env python3
"""
Generate seed_word_queue.sql with top-10k common English words.

Usage:
    python scripts/generate_seed_sql.py > scripts/seed_word_queue.sql

Word list source: COCA (Corpus of Contemporary American English) frequency data.
Priority assignment:
    1 = top 1,000 words  (most common)
    2 = 1,001–5,000
    3 = 5,001–10,000

The list below is a curated subset. For the full 10k COCA list, download from:
    https://www.wordfrequency.info/  (free top-5k, paid for full list)
or use the freely available BNC/SUBTLEX lists.
"""

# fmt: off
# Top 1,000 most common English content words (skip pure function words)
PRIORITY_1 = [
    "time", "year", "people", "way", "day", "man", "woman", "child", "world",
    "life", "hand", "part", "place", "case", "week", "company", "system",
    "program", "question", "work", "government", "number", "night", "point",
    "home", "water", "room", "mother", "area", "money", "story", "fact",
    "month", "lot", "right", "study", "book", "eye", "job", "word", "business",
    "issue", "side", "kind", "head", "house", "service", "friend", "father",
    "power", "hour", "game", "line", "end", "among", "never", "last", "found",
    "still", "learn", "plant", "cover", "food", "sun", "four", "thought",
    "plan", "city", "play", "small", "number", "street", "nothing", "move",
    "try", "kind", "hand", "picture", "again", "change", "off", "play",
    "spell", "air", "away", "animal", "house", "point", "page", "letter",
    "mother", "answer", "found", "study", "still", "learn", "should", "america",
    "world", "high", "every", "near", "add", "food", "between", "own",
    "below", "country", "plant", "last", "school", "father", "keep", "tree",
    "never", "start", "city", "earth", "eye", "light", "thought", "head",
    "under", "story", "saw", "left", "night", "few", "open", "seem",
    "together", "next", "white", "children", "begin", "got", "walk", "example",
    "ease", "paper", "group", "always", "music", "those", "both", "mark",
    "often", "letter", "until", "mile", "river", "car", "feet", "care",
    "second", "enough", "plain", "girl", "usual", "young", "ready", "above",
    "ever", "red", "list", "though", "feel", "talk", "bird", "soon", "body",
    "dog", "family", "direct", "pose", "leave", "song", "measure", "door",
    "product", "black", "short", "numeral", "class", "wind", "question",
    "happen", "complete", "ship", "area", "half", "rock", "order", "fire",
    "south", "problem", "piece", "told", "knew", "pass", "since", "top",
    "whole", "king", "space", "heard", "best", "hour", "better", "true",
    "during", "hundred", "five", "remember", "step", "early", "hold",
    "west", "ground", "interest", "reach", "fast", "verb", "sing", "listen",
    "six", "table", "travel", "less", "morning", "ten", "simple", "several",
    "vowel", "toward", "war", "lay", "against", "pattern", "slow", "center",
    "love", "person", "money", "serve", "appear", "road", "map", "rain",
    "rule", "govern", "pull", "cold", "notice", "voice", "unit", "power",
    "town", "fine", "drive", "lead", "cry", "dark", "machine", "note",
    "wait", "plan", "figure", "star", "box", "noun", "field", "rest",
    "able", "pound", "done", "beauty", "drive", "stood", "contain", "front",
    "teach", "week", "final", "gave", "green", "quick", "develop", "ocean",
    "warm", "free", "minute", "strong", "special", "mind", "behind", "clear",
    "tail", "produce", "fact", "street", "inch", "multiply", "nothing", "course",
    "stay", "wheel", "full", "force", "blue", "object", "decide", "surface",
    "deep", "moon", "island", "foot", "system", "busy", "test", "record",
    "boat", "common", "gold", "possible", "plane", "stead", "dry", "wonder",
    "laugh", "thousand", "ago", "ran", "check", "game", "shape", "equate",
    "miss", "brought", "heat", "snow", "tire", "bring", "yes", "distant",
    "fill", "east", "paint", "language", "among", "grand", "ball", "yet",
    "wave", "drop", "heart", "present", "heavy", "dance", "engine", "position",
    "arm", "wide", "sail", "material", "size", "vary", "settle", "speak",
    "weight", "general", "ice", "matter", "circle", "pair", "include",
    "divide", "syllable", "felt", "perhaps", "pick", "sudden", "count",
    "square", "reason", "length", "represent", "art", "subject", "region",
    "energy", "hunt", "probable", "bed", "brother", "egg", "ride", "cell",
    "believe", "fraction", "forest", "sit", "race", "window", "store", "summer",
    "train", "sleep", "prove", "lone", "leg", "exercise", "wall", "catch",
    "mount", "wish", "sky", "board", "joy", "winter", "sat", "written",
    "wild", "instrument", "kept", "glass", "grass", "cow", "job", "edge",
    "sign", "visit", "past", "soft", "fun", "bright", "gas", "weather",
    "month", "million", "bear", "finish", "happy", "hope", "flower", "clothe",
    "strange", "gone", "jump", "baby", "eight", "village", "meet", "root",
    "buy", "raise", "solve", "metal", "whether", "push", "seven", "paragraph",
    "third", "shall", "held", "hair", "describe", "cook", "floor", "either",
    "result", "burn", "hill", "safe", "cat", "century", "consider", "type",
    "law", "bit", "coast", "copy", "phrase", "silent", "tall", "sand",
    "soil", "roll", "temperature", "finger", "industry", "value", "fight",
    "false", "north", "open", "seem", "beauty", "together", "dark", "broke",
    "suit", "current", "lift", "rose", "continue", "block", "chart", "hat",
    "sell", "success", "company", "subtract", "event", "particular", "deal",
    "swim", "term", "opposite", "wife", "shoe", "shoulder", "spread", "arrange",
    "camp", "invent", "cotton", "born", "determine", "quart", "nine", "truck",
    "noise", "level", "chance", "gather", "shop", "stretch", "throw", "shine",
    "property", "column", "molecule", "select", "wrong", "gray", "repeat",
    "require", "broad", "prepare", "salt", "nose", "plural", "anger",
    "claim", "continent", "oxygen", "sugar", "death", "pretty", "skill",
    "women", "season", "solution", "magnet", "silver", "thank", "branch",
    "match", "suffix", "especially", "fig", "afraid", "huge", "sister",
    "steel", "discuss", "forward", "similar", "guide", "experience", "score",
    "apple", "bought", "led", "pitch", "coat", "mass", "card", "band",
    "rope", "slip", "win", "dream", "evening", "condition", "feed", "tool",
    "total", "basic", "smell", "valley", "nor", "double", "seat", "arrive",
    "master", "track", "parent", "shore", "division", "sheet", "substance",
    "favor", "connect", "post", "spend", "chord", "fat", "glad", "original",
    "share", "station", "dad", "bread", "charge", "proper", "bar", "offer",
    "segment", "slave", "duck", "instant", "market", "degree", "populate",
    "chick", "dear", "enemy", "reply", "drink", "occur", "support", "speech",
    "nature", "range", "steam", "motion", "path", "liquid", "log", "meant",
    "quotient", "teeth", "shell", "neck", "oxygen",
]

# Priority 2 words (1,001–5,000) — intermediate frequency
PRIORITY_2 = [
    "abandon", "ability", "absence", "absolute", "absorb", "abstract",
    "accept", "access", "accident", "accompany", "accomplish", "account",
    "accurate", "achieve", "acknowledge", "acquire", "action", "active",
    "actual", "adapt", "addition", "adequate", "adjust", "administration",
    "admire", "adopt", "advance", "advantage", "advertise", "advice",
    "affect", "afford", "agency", "agree", "agriculture", "alarm",
    "allocate", "allow", "alternative", "analyze", "announce", "annual",
    "apply", "approach", "approve", "argue", "aspect", "assess",
    "assume", "attach", "attempt", "attitude", "authority", "available",
    "aware", "balance", "benefit", "border", "capable", "capacity",
    "capital", "category", "cause", "challenge", "characteristic", "citizen",
    "civil", "claim", "climate", "collect", "combine", "commit",
    "communicate", "community", "complex", "concept", "concern", "confirm",
    "conflict", "consequence", "contribute", "control", "create", "crime",
    "culture", "current", "damage", "debate", "decide", "define",
    "democracy", "demonstrate", "depend", "design", "detail", "develop",
    "difference", "difficult", "discover", "discuss", "distance", "document",
    "domestic", "dominant", "economy", "education", "effect", "effort",
    "elect", "element", "eliminate", "emotion", "enable", "encourage",
    "environment", "establish", "evaluate", "evidence", "examine", "exist",
    "expand", "expert", "explain", "explore", "express", "extend",
    "feature", "focus", "foreign", "formal", "freedom", "function",
    "fundamental", "generate", "global", "growth", "health", "identify",
    "ignore", "impact", "implement", "indicate", "individual", "information",
    "institution", "introduce", "involve", "issue", "knowledge", "leader",
    "legal", "limit", "maintain", "majority", "manage", "medical",
    "method", "model", "movement", "multiple", "national", "negative",
    "network", "observe", "obtain", "occur", "office", "operate",
    "opportunity", "option", "organize", "particular", "perform", "physical",
    "policy", "political", "positive", "potential", "present", "prevent",
    "primary", "principle", "produce", "professional", "protect", "provide",
    "purpose", "quality", "reduce", "reflect", "refuse", "region",
    "relate", "release", "remain", "remove", "require", "research",
    "resource", "respond", "responsibility", "result", "reveal", "role",
    "secure", "significant", "situation", "society", "solution", "standard",
    "strategy", "structure", "successful", "suggest", "supply", "support",
    "technology", "theory", "tradition", "transfer", "treatment", "trend",
    "unique", "various", "violence", "vision", "welfare", "concept",
    "achieve", "acknowledge", "acquire", "action", "adapt", "administration",
    "advance", "advantage", "advertise", "affect", "agency", "agriculture",
    "allocate", "analyze", "announce", "annual", "apply", "approach",
    "approve", "argue", "assess", "assume", "attempt", "attitude",
    "authorize", "available", "balance", "benefit", "border", "capable",
    "capital", "category", "challenge", "characteristic", "citizen", "civil",
    "climate", "collect", "combine", "commit", "communicate", "community",
    "component", "composition", "comprehensive", "concentration", "conclusion",
    "consequence", "conservative", "considerable", "consideration", "consistent",
    "construction", "contemporary", "contribute", "controversial", "cooperation",
    "corporate", "corruption", "creative", "criticism", "declaration", "decrease",
    "dedication", "democracy", "departure", "deployment", "depression", "deputy",
    "describe", "destruction", "determination", "direction", "disadvantage",
    "disaster", "discrimination", "distribution", "diversity", "domination",
    "dramatic", "economic", "effectiveness", "elaborate", "emergency", "emphasis",
    "employment", "enforcement", "engagement", "enormous", "enterprise",
    "equation", "establishment", "estimation", "examination", "exception",
    "execution", "exhibition", "expectation", "expenditure", "experience",
    "explanation", "exploitation", "expression", "extensive", "extraordinary",
    "facilitation", "familiar", "fascination", "financial", "flexibility",
    "foundation", "freedom", "generation", "geographical", "governance",
    "guarantee", "historical", "imagination", "implementation", "important",
    "improvement", "independence", "industrial", "inevitable", "infrastructure",
    "initiative", "innovation", "inspection", "intelligence", "interaction",
    "interpretation", "intervention", "investigation", "invitation", "involvement",
    "isolation", "justification", "legislation", "liberation", "limitation",
    "literature", "management", "measurement", "mechanism", "migration",
    "modification", "motivation", "movement", "nationalism", "negotiation",
    "obligation", "observation", "operation", "opposition", "organization",
    "orientation", "participation", "partnership", "perception", "performance",
    "perspective", "phenomenon", "philosophy", "population", "position",
    "possession", "possibility", "preparation", "presentation", "preservation",
    "problem", "production", "projection", "proportion", "prosecution",
    "protection", "provision", "publication", "qualification", "recognition",
    "recommendation", "regulation", "relationship", "representation", "requirement",
    "resolution", "respect", "restoration", "revolution", "satisfaction",
    "selection", "separation", "settlement", "significance", "specification",
    "stability", "statement", "strengthening", "submission", "substantial",
    "supervision", "survival", "sustainability", "transformation", "transition",
    "transportation", "understanding", "utilization", "validation", "variation",
    "verification", "vulnerability", "welfare", "widespread", "withdrawal",
    "abundance", "acceptance", "adaptation", "affection", "aggression",
    "ambiguity", "ambition", "anticipation", "appreciation", "aspiration",
    "assumption", "authenticity", "autonomy", "awareness", "behavior",
    "collaboration", "compassion", "competence", "complexity", "confidence",
    "confrontation", "consciousness", "creativity", "curiosity", "dedication",
    "dependency", "determination", "dignity", "discipline", "discovery",
    "dominance", "efficiency", "empathy", "endurance", "equality", "excellence",
    "exhaustion", "expectation", "expertise", "exploration", "expression",
    "failure", "familiarity", "fascination", "frustration", "fulfillment",
    "gratitude", "greatness", "humility", "imagination", "importance",
    "improvement", "inclusivity", "independence", "individuality", "influence",
    "innovation", "inspiration", "integrity", "intelligence", "intention",
    "intuition", "justice", "kindness", "leadership", "legitimacy", "loneliness",
    "loyalty", "mastery", "meaning", "mindfulness", "motivation", "optimism",
    "passion", "patience", "perseverance", "perspective", "positivity",
    "power", "purpose", "resilience", "responsibility", "self-awareness",
    "sensitivity", "simplicity", "sincerity", "solidarity", "spirituality",
    "strength", "sustainability", "sympathy", "tolerance", "transparency",
    "trust", "uncertainty", "understanding", "unity", "urgency", "value",
    "vulnerability", "wisdom", "serenity", "harmony", "grace", "dignity",
    "enlightenment", "compassionate", "perseverant", "benevolent", "magnanimous",
    "eloquent", "vivacious", "melancholy", "nostalgia", "ephemeral", "ethereal",
    "sublime", "tranquil", "jubilant", "forlorn", "elated", "serene",
    "profound", "whimsical", "luminous", "radiant", "somber", "enigmatic",
    "celestial", "poignant", "eloquence", "solitude", "introspection",
    "retrospection", "contemplation", "meditation", "revelation", "illumination",
    "transformation", "redemption", "salvation", "liberation", "emancipation",
    "renaissance", "revolution", "enlightenment", "renaissance", "awakening",
    "renewal", "regeneration", "restoration", "reconciliation", "forgiveness",
    "acceptance", "surrender", "resilience", "perseverance", "endurance",
    "fortitude", "courage", "bravery", "valor", "heroism", "sacrifice",
    "devotion", "dedication", "commitment", "loyalty", "fidelity", "integrity",
    "honesty", "sincerity", "authenticity", "humility", "gratitude", "empathy",
    "compassion", "benevolence", "generosity", "charity", "philanthropy",
    "altruism", "selflessness", "magnanimity", "nobility", "righteousness",
    "justice", "fairness", "equity", "equality", "freedom", "liberty",
    "sovereignty", "democracy", "republic", "constitution", "legislation",
    "regulation", "governance", "administration", "bureaucracy", "diplomacy",
    "negotiation", "mediation", "arbitration", "resolution", "reconciliation",
    "alliance", "coalition", "federation", "confederation", "partnership",
    "collaboration", "cooperation", "solidarity", "unity", "cohesion",
    "integration", "inclusion", "diversity", "plurality", "multiculturalism",
    "cosmopolitanism", "globalization", "internationalism", "universalism",
    "humanism", "secularism", "liberalism", "conservatism", "progressivism",
    "pragmatism", "idealism", "realism", "nationalism", "patriotism",
    "citizenship", "identity", "heritage", "tradition", "culture", "civilization",
]

# Priority 3 words (5,001–10,000) — less common but important vocabulary
PRIORITY_3 = [
    "abate", "aberration", "abhor", "abide", "abjure", "abnegate", "abolish",
    "abominate", "abrasion", "abrogate", "absolve", "abstain", "abstinence",
    "abstruse", "abysmal", "accolade", "acrimony", "adamant", "admonish",
    "adroit", "adulation", "adversity", "affable", "affinity", "affluence",
    "agile", "agrarian", "alacrity", "allegory", "alleviate", "aloof",
    "altercation", "altruistic", "amalgam", "ambivalent", "ameliorate",
    "amiable", "amicable", "amorphous", "anachronism", "analogy", "anarchy",
    "anecdote", "animosity", "anomaly", "antagonism", "antithesis", "apathy",
    "appease", "apprehension", "apt", "arbiter", "archaic", "ardent",
    "ardor", "aristocracy", "articulate", "ascertain", "ascetic", "aspire",
    "assiduous", "assuage", "astute", "atrophy", "attentive", "audacious",
    "austere", "avarice", "avid", "banal", "bastion", "belligerent",
    "benign", "bias", "blatant", "blight", "brevity", "brusque",
    "buoyant", "calamity", "candor", "capitulate", "carnage", "catalyst",
    "caustic", "censure", "charisma", "circumspect", "clairvoyant", "clemency",
    "coerce", "cogent", "cohesive", "complacent", "conciliate", "condescend",
    "confound", "congenial", "consternation", "contemplative", "contrite",
    "convergence", "conviction", "copious", "covert", "credulity", "culpable",
    "curtail", "cynicism", "dauntless", "dearth", "debacle", "decorum",
    "defunct", "delineate", "desolation", "despondent", "devious", "dilemma",
    "discern", "disdain", "disparage", "dissent", "dogma", "dubious",
    "duplicity", "ebullience", "eccentric", "elude", "embellish", "empirical",
    "emulate", "enervate", "equanimity", "erudite", "esteem", "euphoria",
    "evasive", "exacerbate", "exalt", "exemplary", "exhaustive", "exonerate",
    "exorbitant", "expedient", "explicit", "exuberant", "fallacious",
    "fervent", "feign", "fervid", "flagrant", "flamboyant", "fledgling",
    "flourish", "fluctuate", "forthright", "frugal", "fundamental",
    "garrulous", "genuine", "grim", "groundless", "guile", "habituate",
    "haughty", "hegemony", "heretical", "hierarchy", "hypocrite", "hypothetical",
    "ignominious", "immutable", "impartial", "impeccable", "imperious",
    "impervious", "implicit", "inadvertent", "incisive", "indignant",
    "indolent", "inevitable", "inextricable", "infallible", "inherent",
    "iniquity", "insidious", "intransigent", "intrinsic", "inveterate",
    "irrefutable", "laconic", "latent", "laudable", "lethargic", "liability",
    "lofty", "magnanimous", "malleable", "meticulous", "misanthrope",
    "mitigate", "mollify", "monotony", "negligent", "nonchalant", "notorious",
    "nuance", "obdurate", "oblique", "obscure", "obstinate", "odious",
    "onerous", "opaque", "ostentatious", "ostracize", "pacify", "paradigm",
    "paradox", "paramount", "partisan", "passive", "pedantic", "pernicious",
    "pervasive", "petulant", "placate", "plausible", "polarize", "pretentious",
    "proliferate", "prudent", "pugnacious", "quandary", "querulous", "rancor",
    "rationalize", "recalcitrant", "rectify", "redress", "relentless",
    "reprehensible", "reproach", "resilient", "resolute", "reticent",
    "rouse", "sanction", "sardonic", "scrutinize", "sinister", "skeptical",
    "solemn", "speculative", "spurious", "stoic", "stringent", "submissive",
    "subtle", "superfluous", "suppress", "susceptible", "tenacious", "terse",
    "timorous", "transgress", "treacherous", "trivial", "turbulent", "tyrant",
    "ubiquitous", "unjust", "unpredictable", "unscrupulous", "vacillate",
    "vehement", "verbose", "vicarious", "vigilant", "villainous", "vindictive",
    "volatile", "voracious", "wary", "zealous", "acumen", "aesthetic",
    "affectation", "ambiguity", "amelioration", "amplitude", "animadversion",
    "antidote", "aphorism", "apotheosis", "archetype", "articulation",
    "assimilation", "atrocity", "autonomy", "axiom", "bellicose", "beneficence",
    "bestow", "capitulation", "catharsis", "circumlocution", "cogitation",
    "commensurate", "compunction", "connotation", "consternate", "contention",
    "conundrum", "corollary", "credibility", "criterion", "deference",
    "deleterious", "demeanor", "deprecation", "derision", "dialectic",
    "dichotomy", "diffidence", "discrepancy", "disingenuous", "dissipate",
    "distortion", "divergence", "effrontery", "eloquence", "eminence",
    "empowerment", "encomium", "epistemology", "equivocal", "erroneous",
    "estrangement", "exigency", "expediency", "fabrication", "fallibility",
    "fanaticism", "forbearance", "fraternization", "grandiloquent", "gravity",
    "hegemony", "hyperbole", "iconoclast", "ideological", "immense",
    "imperialism", "impunity", "incorruptible", "indictment", "indulgence",
    "ineptitude", "infamy", "ingenuity", "insinuation", "interrogation",
    "intimidation", "intolerance", "invective", "irreverence", "isolation",
    "jurisprudence", "kinship", "leniency", "licentiousness", "lineage",
    "lucid", "malevolence", "manifestation", "marginalization", "mendacity",
    "metaphor", "methodology", "militarism", "misconception", "moderation",
    "morality", "mysticism", "narcissism", "nihilism", "obstruction",
    "omnipotence", "oppression", "orthodoxy", "paternalism", "patronization",
    "perfidy", "perpetration", "persecution", "petulance", "philanthropy",
    "platitude", "polarization", "pragmatism", "precedent", "predisposition",
    "prerogative", "presupposition", "privilege", "proclivity", "propagation",
    "propensity", "propitiate", "proscription", "provocation", "rationalism",
    "reductionism", "reformation", "relativism", "renunciation", "repudiation",
    "resentment", "retrospect", "romanticism", "sanctimony", "schism",
    "skepticism", "speculation", "subjectivity", "supremacy", "symbolism",
    "symptomatic", "totalitarianism", "transcendence", "tribalism", "tyranny",
    "unilateralism", "universality", "utilitarianism", "utopianism", "veneration",
    "verbosity", "virulence", "vituperation", "xenophobia", "zeitgeist",
    # Islamic/Arabic loanwords important for Urdu context
    "alchemy", "algorithm", "algebra", "amalgam", "assassin", "caliber",
    "candy", "cipher", "coffee", "cotton", "elixir", "hazard", "jasmine",
    "lemon", "magazine", "muslin", "orange", "saffron", "spinach", "sugar",
    "syrup", "tariff", "zenith",
    # Academic / literary
    "abscissa", "absurdism", "allegiance", "alliteration", "anachronistic",
    "anagnorisis", "anthropomorphism", "aphoristic", "arcadian", "archival",
    "aristotelian", "assonance", "ballad", "bildungsroman", "byzantine",
    "canon", "cathartic", "chronicle", "climactic", "colloquial",
    "connotative", "couplet", "diction", "didactic", "dramatic",
    "elegy", "ellipsis", "empathy", "epic", "epigram", "episodic",
    "euphemism", "exposition", "fable", "figurative", "foil", "foreshadow",
    "genre", "gothic", "haiku", "hubris", "hyperbolic", "imagery",
    "irony", "juxtapose", "lament", "limerick", "lyrical", "metaphorical",
    "motif", "mythology", "narrative", "nemesis", "novella", "omniscient",
    "onomatopoeia", "oxymoron", "parable", "pathos", "persona", "persuasion",
    "plot", "poetry", "protagonist", "rhetoric", "rhyme", "romance",
    "satire", "simile", "soliloquy", "sonnet", "stanza", "subplot",
    "suspense", "symbolize", "syntax", "theme", "tragedy", "utopia",
    "verse", "villain", "voice", "wistful",
]
# fmt: on


def deduplicate(words: list[str]) -> list[str]:
    seen: set[str] = set()
    result = []
    for w in words:
        w = w.strip().lower()
        if w and w not in seen:
            seen.add(w)
            result.append(w)
    return result


def main() -> None:
    p1 = deduplicate(PRIORITY_1)
    p2 = deduplicate(PRIORITY_2)
    p3 = deduplicate(PRIORITY_3)

    # Remove P1 from P2/P3, P2 from P3 (no duplicates across priorities)
    p1_set = set(p1)
    p2 = [w for w in p2 if w not in p1_set]
    p2_set = set(p2)
    p3 = [w for w in p3 if w not in p1_set and w not in p2_set]

    print("-- UrduMeaning: Seed word_queue with common English words")
    print("-- Generated by scripts/generate_seed_sql.py")
    print("-- Priority 1 = top ~1k, Priority 2 = 1k-5k, Priority 3 = 5k-10k")
    print("-- Run: psql -U postgres -d lughatai -f scripts/seed_word_queue.sql")
    print()
    print("INSERT INTO word_queue (word, priority) VALUES")

    rows: list[str] = []
    for w in p1:
        rows.append(f"('{w}', 1)")
    for w in p2:
        rows.append(f"('{w}', 2)")
    for w in p3:
        rows.append(f"('{w}', 3)")

    for i, row in enumerate(rows):
        suffix = "," if i < len(rows) - 1 else ""
        print(f"{row}{suffix}")

    print("ON CONFLICT (word) DO NOTHING;")
    print()
    print(f"-- Total words: {len(rows)} "
          f"(P1: {len(p1)}, P2: {len(p2)}, P3: {len(p3)})")


if __name__ == "__main__":
    main()
