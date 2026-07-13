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

    static let firstRunSchedule: [ScheduleStep] = [
        ScheduleStep(entryID: "apple-music",   reward: StepReward(insight: true)),
        ScheduleStep(entryID: "fit-photo",     reward: StepReward(insight: true, cosmetic: .midnight)),
        ScheduleStep(entryID: "latest-book",   reward: StepReward(insight: false)),
        ScheduleStep(entryID: "youtube",       reward: StepReward(insight: true)),
        ScheduleStep(entryID: "weekend",       reward: StepReward(insight: true)),
        ScheduleStep(entryID: "comfort-movie", reward: StepReward(insight: false, cosmetic: .clay)),
        ScheduleStep(entryID: "photos",        reward: StepReward(insight: true)),
        ScheduleStep(entryID: "bookshelf",     reward: StepReward(insight: true, cosmetic: .moss)),
        ScheduleStep(entryID: "contacts",      reward: StepReward(insight: true)),
        ScheduleStep(entryID: "calendar",      reward: StepReward(insight: true)),
    ]

    /// After the schedule is exhausted, cooldown offers every catalog entry that
    /// the curated schedule never used, prompts first, then any unscheduled source.
    static let cooldownPool: [NodeCatalogEntry] = {
        let scheduled = Set(firstRunSchedule.map(\.entryID))
        let remaining = all.filter { !scheduled.contains($0.id) }
        return remaining.filter { $0.captureKind != .source } + remaining.filter { $0.captureKind == .source }
    }()

    static func entry(_ id: String) -> NodeCatalogEntry? { all.first { $0.id == id } }
}
