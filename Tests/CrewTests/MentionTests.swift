import Testing

private func bot(_ name: String, title: String) -> Bot {
    Bot(name: name, displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta(title: title))
}

@Test func removingMentionDropsHandleAndTitleTagsOnly() {
    let ada = bot("ada", title: "Ada Lovelace")
    let text = "Loop in @ada, @Ada-Lovelace and @scout"
    #expect(removingMention(of: ada, from: text) == "Loop in, and @scout")
    #expect(mentionedBots(in: removingMention(of: ada, from: text), among: [ada]).isEmpty)
}
