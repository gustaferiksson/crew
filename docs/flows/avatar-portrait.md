# Generate a portrait (#352)

Generate a bot's avatar picture with the server's image backend, like Hermes Desktop's Generate tab (`apps/desktop/src/plugins/hermes-bots/avatar-picker.tsx`, `avatar-image.ts`). The result is a photo avatar: it goes through `ProfileDraft.pickPhoto` and saves with `profiles.set_asset` exactly like a chosen photo, so there is one storage path and every surface that shows a photo shows a portrait.

## Server

- `image.generate` (`tui_gateway/methods_images.py`, Hermes v0.23.1) takes only params, no session or profile: availability is gateway-wide, so one answer covers every bot.
- `{probe: true}` answers `{available}`. The real server answered `{"available": false}` on 2026-11-14 (no backend configured), recorded in `Tests/fixtures/image.generate.probe.v0.23.1.json`; a generate there answers `{available: false, success: false, error: "No image generation backend configured …"}` (`image.generate.unavailable.v0.23.1.json`).
- A generate answers `{available: true, success: true, image, image_data?}`. `image_data` is a data URL and is omitted when the gateway couldn't download the backend's result; then `image` is the backend's URL or a gateway file path. Crew is always remote, so only an `https` `image` is fetched; a path is a failure. The success shape is built from source (`image.generate.success.contract.v0.23.1.json`), since no backend exists to record one.
- Remote backends take 40 to 60 s (Desktop's comment). Crew waits up to 90 s, Desktop's bound, on every generate (Desktop's custom-description path forgot it and falls under the 30 s default).
- No server-side cancel exists.

## Prompt (Desktop's wording)

- Description field blank: `Cute minimal robot avatar for an AI agent named "<who>". Friendly simple mascot face, bold flat vector style, solid color background, centered, no text.` where `<who>` is the display title (or the profile name when blank) and the description joined by ` — `. Desktop leaves the role out; so does Crew.
- Description typed: `<text>. Avatar for an AI agent: centered, bold flat vector style, solid color background, no text.`
- `aspect_ratio: square`, default `max_bytes`.

## Surface: the Look editor (iPhone sheet, Mac popover)

The bot inspector's avatar opens the Look editor (`LookEditor` in `BotInspector.swift`), which already holds Choose Photo… and Remove Photo. A new "Portrait" section sits right under that photo section:

- A multi-line text field, placeholder "Describe the portrait", 1 to 3 lines.
- A "Generate Portrait" button (`sparkles`).
- Footer: "Leave blank to use the bot's name and description." (Desktop's hint, shortened), or the failure text in red.

Hidden state: the section only shows when the probe answered `available: true` on the current gateway. No backend, a failed probe and not yet probed (including signed out or never connected) show nothing, so the editor looks exactly like today. Once a backend is known, going offline keeps the section with Generate disabled until the gateway reconnects. The inspector probes once per gateway and keeps a `true`; the editor re-checks a `false` each time it opens (Desktop's `probeImagen`), so a backend enabled later appears without the section popping in on every open.

The generate belongs to the inspector (the container), like the chosen-photo task, not to the editor: the Mac popover closes on any click outside it, and a stray click must not throw away a 40 to 60 s render.

## States

- **Generating:** the button row becomes a small `ProgressView`, "Generating…" and a Cancel button; the text field is disabled. The rest of the editor stays usable (shapes, colours). Indeterminate progress, since the server reports none.
- **Cancel:** returns the row to Generate at once and discards the reply when it arrives (the server finishes the render; nothing reaches the draft).
- **Done or dismissing the editor while generating:** the render continues; its result lands in the draft and autosaves like a photo. Reopening the editor shows Generating… with Cancel again. Leaving the bot (another bot selected, the iPhone page popped) drops it.
- **Changing the look while generating:** choosing a photo, a shape or a colour, Remove Photo and Reset to Default cancel the generate, so the latest choice wins. The expression doesn't (it draws only on shape avatars).
- **Success:** the image becomes the draft's photo (square aspect, drawn like any photo), the editor's preview and the inspector header avatar switch to it, and the inspector autosaves it at once with the existing Saving…/Saved line. The description text stays so a second Generate tries again.
- **Failure:** red footer text, Generate available again: the server's or the RPC's own message when there is one (for example the no-backend text when a backend was removed since the probe), otherwise "Crew couldn't generate a portrait. Check your connection and try again." (timeout, lost connection, a reply with no usable image: no `image_data`, no `https` `image`, or bytes ImageIO can't read). Unreadable bytes never reach the inspector's chosen-photo notice. A new Generate or Cancel clears the text.
- **Offline mid-generation:** the call fails when the socket drops (or at 90 s) and shows the connection failure.
- **Replace and reset:** a portrait replaces any photo, a chosen photo replaces a portrait, Remove Photo and Reset to Default clear it and go back to the shape avatar (existing photo behaviour, unchanged). A shape or colour pick also removes it, as for photos.
- **Save failure:** the inspector's existing "Couldn't save the photo." notice with Try Again.
- **Long content:** the description field grows to 3 lines then scrolls; failure text wraps.
- **Light/dark:** system form rows, tint and red; the portrait itself is an opaque image like a photo.

## Not included

- **New Bot:** its Appearance page has no photo path today (shape, colour and expression only, `photo: nil`), so it gets no Generate either; adding photos to New Bot is its own change.
- **Rooms:** Desktop also generates room pictures; Crew rooms have no picture.
- **Image Playground:** Apple's own way to make an avatar (`imagePlaygroundSheet`, as in Contacts) needs no server backend. The issue asks for Desktop's server path so the portrait matches what Desktop makes and works on Macs and iPhones without Apple Intelligence; Image Playground is a possible follow-up.
- Desktop's Pet tab and its "No image model available" text: Crew hides the section instead of explaining a server setting the user can't change from Crew.

## Verification

- Unit (`PortraitTests`): the recorded probe hides the section; Cancel drops a late reply (no failure, no photo); the recorded no-backend generate fails with the server's text; the contract success reply resolves `image_data` to bytes and fails on a gateway path (the `https` fallback is untested: it needs the network); the prompt matches Desktop's two templates; a resolved portrait saved through `ProfileDraft.pickPhoto` sets `photoChange` to `.replace` and `imageKind` to `photo`. The inline-data, Cancel, prompt and unreadable-bytes tests were shown failing against a mutated implementation.
- Real server: a throwaway probe calls Crew's own availability check and gets `false` (hidden state). No backend, so no real generate; the success path is verified only against the source shape.
- Renders (`docs/flows/renders/avatar-portrait-*.png`), with the generator's state injected by the fixture (the real server answers `false`): `inspector-look` (hidden, unchanged) and new `inspector-look-portrait` (available, showing a failure) and `inspector-look-generating` (Generating… with Cancel), iPhone and Mac, light and dark.
