import Foundation

struct NodeCatalogEntry: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let captureKind: NodeCaptureKind
    let sourceRoute: NodeRoute?
    let prompt: PromptSpec?
    let glyph: String
    let brainNodeID: BrainNodeID
}

enum NodeCatalog {
    static let all: [NodeCatalogEntry] = source + prompts

    static let source: [NodeCatalogEntry] = [
        .init(id: "apple-music", title: "your other music", subtitle: "connect Apple Music so I hear the rest",
              captureKind: .source, sourceRoute: .appleMusic, prompt: nil, glyph: "music.note", brainNodeID: .appleMusic),
        .init(id: "youtube", title: "what you watch", subtitle: "connect YouTube so I see past the music",
              captureKind: .source, sourceRoute: .youtube, prompt: nil, glyph: "play.rectangle.fill", brainNodeID: .youtube),
        .init(id: "photos", title: "your camera roll", subtitle: "let me see what you point a camera at",
              captureKind: .source, sourceRoute: .photos, prompt: nil, glyph: "photo.on.rectangle", brainNodeID: .photos),
        .init(id: "contacts", title: "your people", subtitle: "who you keep close says a lot",
              captureKind: .source, sourceRoute: .contacts, prompt: nil, glyph: "person.2.fill", brainNodeID: .contacts),
        .init(id: "calendar", title: "how you spend time", subtitle: "connect your calendar",
              captureKind: .source, sourceRoute: .calendar, prompt: nil, glyph: "calendar", brainNodeID: .calendar),
    ]

    static let prompts: [NodeCatalogEntry] = [
        // Base-phase prompts (see `baseEntryIDs`): the first foundation the worm
        // grows from, alongside the Photos source node.
        .init(id: "lock-screen", title: "your lock screen", subtitle: "the first thing you see",
              captureKind: .photo, sourceRoute: nil, prompt: PromptSpec(), glyph: "lock.iphone", brainNodeID: .prompts),
        .init(id: "ideal-saturday", title: "your ideal saturday", subtitle: "in three words",
              captureKind: .text, sourceRoute: nil, prompt: PromptSpec(placeholder: "three words"), glyph: "sun.max.fill", brainNodeID: .prompts),
        // Banked fun prompts — never surface in the base, they ride the drip.
        .init(id: "last-obsession", title: "the last thing you got obsessed with", subtitle: "a show, a snack, a rabbit hole",
              captureKind: .text, sourceRoute: nil, prompt: PromptSpec(placeholder: "whatever it was"), glyph: "flame.fill", brainNodeID: .prompts),
        .init(id: "nightstand", title: "what's on your nightstand", subtitle: "however it actually looks",
              captureKind: .photo, sourceRoute: nil, prompt: PromptSpec(), glyph: "bed.double.fill", brainNodeID: .prompts),
        .init(id: "everyday-order", title: "your everyday order", subtitle: "coffee, drink, whatever you always get",
              captureKind: .text, sourceRoute: nil, prompt: PromptSpec(placeholder: "the usual"), glyph: "cup.and.saucer.fill", brainNodeID: .prompts),
        .init(id: "window-view", title: "the view out your window", subtitle: "wherever you are right now",
              captureKind: .photo, sourceRoute: nil, prompt: PromptSpec(), glyph: "window.vertical.closed", brainNodeID: .prompts),
        .init(id: "room-corner", title: "a corner of a room you love", subtitle: "yours or anywhere",
              captureKind: .photo, sourceRoute: nil, prompt: PromptSpec(), glyph: "house.fill", brainNodeID: .prompts),
        .init(id: "fit-photo", title: "photo of your fit", subtitle: "so I can see how you dress",
              captureKind: .photo, sourceRoute: nil, prompt: PromptSpec(), glyph: "camera.fill", brainNodeID: .prompts),
        .init(id: "latest-book", title: "the last book you read", subtitle: "title's enough",
              captureKind: .text, sourceRoute: nil, prompt: PromptSpec(placeholder: "title, author, whatever you remember"), glyph: "book.fill", brainNodeID: .prompts),
        .init(id: "weekend", title: "what'd you get up to this weekend", subtitle: "a sentence is plenty",
              captureKind: .text, sourceRoute: nil, prompt: PromptSpec(placeholder: "one line"), glyph: "sun.max.fill", brainNodeID: .prompts),
        .init(id: "comfort-movie", title: "your comfort movie", subtitle: "the one you rewatch",
              captureKind: .choice, sourceRoute: nil,
              prompt: PromptSpec(options: ["rom-com", "action", "A24 sad", "horror", "animation", "a documentary"], allowsFreeText: true),
              glyph: "film.fill", brainNodeID: .prompts),
        .init(id: "bookshelf", title: "snap your bookshelf", subtitle: "or whatever's on the shelf",
              captureKind: .photo, sourceRoute: nil, prompt: PromptSpec(), glyph: "books.vertical.fill", brainNodeID: .prompts),
        .init(id: "stuck-song", title: "a song stuck in your head", subtitle: "right now",
              captureKind: .text, sourceRoute: nil, prompt: PromptSpec(placeholder: "song + artist"), glyph: "music.quarternote.3", brainNodeID: .prompts),
        .init(id: "last-concert", title: "the last show you went to", subtitle: "live music, comedy, anything",
              captureKind: .text, sourceRoute: nil, prompt: PromptSpec(placeholder: "who, and roughly when"), glyph: "ticket.fill", brainNodeID: .prompts),
        .init(id: "desk-now", title: "your desk right now", subtitle: "no cleaning up first",
              captureKind: .photo, sourceRoute: nil, prompt: PromptSpec(), glyph: "camera.viewfinder", brainNodeID: .prompts),
    ]

    /// The first-run foundation: a few prominent apples the user feeds before any
    /// countdown exists. Photos (the camera roll) plus two quick self-reports.
    /// These never appear in the drip schedule or cooldown pool.
    static let baseEntryIDs: [String] = ["photos", "lock-screen", "ideal-saturday"]

    static var baseEntries: [NodeCatalogEntry] { baseEntryIDs.compactMap(entry) }

    /// The drip: everything not in the base, dripped one node per window. The base
    /// three (`photos`, `lock-screen`, `ideal-saturday`) are banked out of here.
    static let firstRunSchedule: [ScheduleStep] = [
        ScheduleStep(entryID: "apple-music",    reward: StepReward(insight: true)),
        ScheduleStep(entryID: "fit-photo",      reward: StepReward(insight: true, cosmetic: .midnight)),
        ScheduleStep(entryID: "latest-book",    reward: StepReward(insight: false)),
        ScheduleStep(entryID: "youtube",        reward: StepReward(insight: true)),
        ScheduleStep(entryID: "weekend",        reward: StepReward(insight: true)),
        ScheduleStep(entryID: "comfort-movie",  reward: StepReward(insight: false, cosmetic: .clay)),
        ScheduleStep(entryID: "last-obsession", reward: StepReward(insight: true)),
        ScheduleStep(entryID: "bookshelf",      reward: StepReward(insight: true, cosmetic: .moss)),
        ScheduleStep(entryID: "contacts",       reward: StepReward(insight: true)),
        ScheduleStep(entryID: "everyday-order", reward: StepReward(insight: true)),
        ScheduleStep(entryID: "calendar",       reward: StepReward(insight: true)),
    ]

    /// After the schedule is exhausted, cooldown offers every catalog entry that
    /// neither the base nor the curated schedule used, prompts first, then any
    /// unscheduled source.
    static let cooldownPool: [NodeCatalogEntry] = {
        let used = Set(firstRunSchedule.map(\.entryID)).union(baseEntryIDs)
        let remaining = all.filter { !used.contains($0.id) }
        return remaining.filter { $0.captureKind != .source } + remaining.filter { $0.captureKind == .source }
    }()

    static func entry(_ id: String) -> NodeCatalogEntry? { all.first { $0.id == id } }
}
