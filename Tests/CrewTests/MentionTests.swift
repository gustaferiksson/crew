import Testing

private func bot(_ name: String, title: String) -> Bot {
    Bot(name: name, displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta(title: title))
}

@Test func mentionSegmentsTagHandleAndTitleTokensOnly() {
    let ada = bot("ada", title: "Ada Lovelace")
    let segments = mentionSegments(in: "@ada loop in @Ada-Lovelace, and @scout", among: [ada])
    #expect(segments == [
        MentionSegment(text: "@ada", bot: ada),
        MentionSegment(text: " loop in ", bot: nil),
        MentionSegment(text: "@Ada-Lovelace", bot: ada),
        MentionSegment(text: ", and @scout", bot: nil),
    ])
}
