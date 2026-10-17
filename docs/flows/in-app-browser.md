# In-app browser for web links (iOS)

On iPhone and iPad a web link tapped anywhere in Crew opens in Safari's in-app browser (`SFSafariViewController`) as a card over whatever is on screen, so the chat stays one swipe away, as in Slack, Reddit and Hermex. On Mac links keep opening in the default browser, the Mac convention.

## Routing (one place)

- iOS sets one `OpenURLAction` on the app root (`CrewApp`). Every `Text` link, `Link` and `openURL` call below it goes through it, sheets and popovers included, since they inherit the root environment.
- `LinkDestination` decides from the URL alone (a pure function, unit-tested):
  - `http`/`https` with a host: in-app.
  - Crew's install page (`https://gustaferiksson.github.io/crew/`, `/crew`, `/crew/index.html`): system. Its Install button is an `itms-services` link, which only Safari itself runs. Other Pages files (`checkout-test.html`, `manifest.plist`) are ordinary web links.
  - Anything else (`mailto:`, `tel:`, `sms:`, `itms-services:`, `crew-mention:`, other app schemes, host-less URLs): system, unchanged from today (`.systemAction`).
- In-app links first try `UIApplication.open` with `universalLinksOnly`: a link an installed app claims (GitHub, YouTube, Maps) opens in that app, as tapping it in Safari would. Only when no app claims it does the card appear. The check is local and takes no visible time.
- The card is presented by UIKit from the topmost presented controller of the foreground key window, so it stacks over a sheet (inspector on iPhone, a search result, another conversation, an expanded mention chat) instead of failing to present. If the topmost controller already is a Safari card (a double tap), the second tap is ignored.
- Presentation is `.pageSheet`, the card the user asked for: content dimmed behind it, Close (Done on older iOS) or a swipe down closes it, full screen in compact height (iPhone landscape), a large centred card on iPad. Trade-off accepted: a pull down at the very top of a page can close the card instead of scrolling. Configuration is the default `SFSafariViewController.Configuration` with `entersReaderIfAvailable` explicitly false; Reader stays one tap away in Safari's own toolbar.
- No `UIApplication.open`/`openURL` call elsewhere needs changing: nothing in Crew opens web URLs directly today.

## Surfaces

- **Bot replies** (markdown `Text` in `MarkdownText`, work-log notes, answers): in-app.
- **A2UI cards**: markdown links in card text (`CrewComponents`, `CrewBlocks`) are `Text` links, so in-app. A2UI's `openUrl` function action is not registered by Crew today and stays inert; out of scope.
- **"Open in Maps"** (`CrewChartMap`): calls `MKMapItem.openMaps`, not `openURL`; unchanged.
- **Mention tags** in user bubbles: `UserBubble`'s own `OpenURLAction` keeps handling `crew-mention:` (opens the peek). User text is not linkified, so a user bubble has no web links (today's behaviour, unchanged).
- **Mention peek**: its text is plain; links appear once it expands to the bot's chat at the large detent, and open the card over that sheet.
- **Inspector, other-conversation viewer, search results** (`ConversationTranscript` renders `TurnView`): sheets on iPhone inherit the root action; the card opens on top, and closing it lands back on the sheet.
- **Update banner** (`Install Crew <v>` in the sidebar): an `itms-services` `Link`, routed to the system as today.
- **Mac**: no override; the default browser for every link, the Mac updater's releases page included.

## States

- **No network / page fails**: Safari's own error page inside the card; Close dismisses it.
- **Signed-out pages**: the card does not share Safari's cookies, so a private page (say a private GitHub PR without the GitHub app) shows a login page. Accepted; the card's own "Open in Safari" is the way out.
- **Long or odd URLs**: Safari shows the host; Crew does not rewrite URLs.
- **Bare URLs** in bot text: `AttributedString(markdown:)` links only `[text](url)` and `<url>`, so a bare `https://…` stays plain text, as today. Out of scope.
- **Long press on a link**: shows the message's own context menu (Copy, Select, Share), as today; no link preview.
- **Select Text sheet**: plain text, links not tappable, as today.
- **Return to chat**: after Close the chat (scroll position and composer draft) is as it was; nothing reloads. The keyboard may need a tap to come back.
- **Background while open**: the card stays presented when the app returns.
- **VoiceOver**: links are in the Links rotor as today; activating one presents the card, which takes focus; Close returns to the chat.
- **Light and dark**: Safari's chrome follows the system. Crew's Dynamic Type does not apply inside the page (Safari's own text size does).
- **iPad with two Crew windows**: the card opens in the foreground-active scene's key window, which is the tapped one in practice. Known limitation if two Crew scenes are both foreground and the tap lands in the non-key one.

## Tests

- Unit (`LinkRoutingTests`): http/https in-app (any case, other Pages files), install page, `mailto:`/`tel:`/`sms:`/`itms-services:`/`crew-mention:`/`maps:`/`file:`/host-less to the system.
- UI (`InAppBrowserUITests`): in `-snapshot layout`, tap the "PR #42" link in the bot reply; the Safari card appears (its Open in Safari button); Close returns to the chat with the reply and composer still there.
- Render: the card over the chat on a private iOS simulator.
