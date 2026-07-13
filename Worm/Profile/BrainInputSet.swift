import Foundation

/// Single registry for user inputs that contribute to personality.
///
/// When a new node or captured input becomes part of "who this user is", add it
/// here first. Profile surfaces should ask this type for brain context instead
/// of manually remembering every node.
@MainActor
struct BrainInputSet {
    let spotify: SpotifyMusicNode
    let appleMusic: AppleMusicNode
    let youtube: YouTubeCultureNode
    let contacts: ContactsNode
    let photos: PhotosNode
    let calendar: CalendarNode
    let selfie: SelfieNode
    let prompts: PromptNode

    func context(read: String?, insights: [Insight]) -> BrainContext {
        BrainSliceBuilder.context(
            spotify: spotify,
            appleMusic: appleMusic,
            youtube: youtube,
            contacts: contacts,
            photos: photos,
            calendar: calendar,
            selfie: selfie,
            prompts: prompts,
            read: read,
            insights: insights
        )
    }

    func slices() -> [NodeBrainSlice] {
        context(read: nil, insights: []).slices
    }
}
