import SwiftUI
import Testing

@Test func theMentionTagRendererWorksOnSwiftUIsAsyncRenderThread() async {
    let conforms = await Task.detached {
        (MentionTagRenderer() as Any) is any TextRenderer && (MentionTag(index: 0) as Any) is any TextAttribute
    }.value
    #expect(conforms)
}
