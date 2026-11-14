# Rooms: send and open attachments (#350)

Room composers are text only. Hermes 0.23.1 rooms take files (`groups.attachment.upload`, `groups.attachment.download`) and Desktop uses them. Crew reuses the Bot Chat's picker, tray, bubble thumbnails, file chips and Quick Look for rooms.

## What Hermes has (v0.23.1, `tui_gateway/methods_groups.py`, `gateway/session_hosted_attachments.py`, `gateway/hosted_room_attachments.py`; Desktop `canonical-group-attachments.tsx`, `canonical-group-history.tsx`, `canonical-group-workspace.tsx`)

- **Upload**: `groups.attachment.upload {room_id, upload_id, kind, name, mime, data_base64}` stores one file as "uploaded" (not yet in the room) and returns `{attachment_id, kind, name, size, mime, sha256, state, …}`. `kind` is `image`, `pdf` or `file`; an image's MIME must match its bytes (PNG, JPEG, GIF, BMP, WebP), a PDF must be a PDF, a `text/*` file must be UTF-8. Reusing an `upload_id` with the same bytes is idempotent. Abandoned uploads are pruned by the server.
- **Send**: `groups.send` takes `payload.attachments`, a list of exactly `{attachment_id, kind, name, size, mime}`. The text may be empty when files are attached. The logged `message.user` carries the same list.
- **Limits** (room store): 8 files per message, 15 MB per file, 25 MB per message (decimal). Stricter than the Bot Chat (8, 25 MB, 50 MB).
- **Download**: `groups.attachment.download {room_id, event_id, attachment_id}` returns the metadata plus `data_base64`.
- **What members get**: images as native vision input; any other file as a `[Shared attachment] file: <path>` line in their prompt.
- **Members on another gateway** (RoomLink peers) are text only (`attachments: false` in the peer catalog). A message with files fails that member's turn before it starts (`refused_before_submit`), logged as `turn.failed`.
- **Member replies** are text only: the only `message.member` publisher (`hosted_room_discussion._settled_effects`) writes `text` alone. The schema allows `attachments` on `message.member` and the driver forwards them to other members (`_event_attachments`), but nothing in 0.23.1 produces one.
- **Transport**: both RPCs carry the whole file base64 in one WebSocket frame (a 15 MB file is a ~20 MB frame). Crew caps inbound frames at 16 MiB today, so it raises the cap to 32 MiB; a bigger frame would drop the connection.
- **Desktop** uploads each file when it is picked, holds Send while an upload runs, shows chips with Download, previews images up to 5 MB inline in the transcript and downloads any file to disk. It gates upload on `groups.capabilities.methods` listing `groups.attachment.upload` and download on `groups.attachment.download`.

## Flow

### Composer (iPhone and Mac)

- **Shown when** the server's `groups.capabilities` lists `groups.attachment.upload` (read on every `gateway.ready`, as the room gate already is). Then the room composer has the Bot Chat's + menu (Camera on an iPhone with a camera, Photos, Files; on the Mac also Paste), and the Mac also takes a drop onto the chat and Cmd+V outside the field. Without the method (older servers) the room composer stays text only, as today: no + and no drop or paste.
- **Tray**: the same pending tray above the field (64 pt thumbnails, file chips, remove button). Images are re-encoded exactly as in a Bot Chat (over 2048 px, HEIC/TIFF, rotated), so a photo always arrives as PNG or JPEG.
- **Limits**: the room's own, checked when a file is added: "<name> is larger than 15 MB.", "Attachments can add up to 25 MB per message.", "You can attach up to 8 files per message.", in the Bot Chat's existing alert. A folder is refused as in a Bot Chat.
- **Send** is enabled with text, files, or both (an image alone is a valid room message, as on the server).
- **Draft**: the tray is the room's, in memory only, like the Bot Chat's (PLAN "Composer, drafts and sends"); the room row shows "Draft: 2 Attachments" when only files are waiting.
- **Offline**: + is disabled and Send is disabled, the field stays editable (existing rule).
- **Send while the room works**: allowed, as a text send is (a plain `groups.send`).

### Sending

- Like the Bot Chat, files are staged when you press Send, not when you pick them, so removing a file from the tray never leaves an upload behind. Desktop uploads at pick; the difference is invisible to the room log.
- On Send the bubble appears at once with the files (thumbnails from the local bytes) and the text, then Crew uploads each file (`upload_id` = the attachment's id, `kind` = `image`, `pdf` for `application/pdf`, else `file`; an image's `mime` from its bytes, since the server compares them, other files' from the name), then sends the message with the manifest and the thread as any send. The tray and draft clear on Send.
- **Failure** (an upload or the send is refused, or the connection drops): the bubble stays, with its files, as "Not sent: <reason>", as any failed room send; the reason is whatever the gateway returns (the probe records what a refused upload says). Files already uploaded are left for the server's prune.
- **Too large or wrong type at the server** (a limit Crew did not catch, a `text/*` file that is not UTF-8): the same "Not sent" with the server's reason.

### The sent message in the transcript

- Your message is a user bubble with its files above it, trailing, exactly like a Bot Chat prompt: one image at 200 pt, several in a 120 pt row that scrolls when it does not fit, other files as chips with a document icon (`doc.richtext` for PDF). A files-only message shows no empty bubble.
- Files posted by you from Desktop or another Crew device are `message.user` too, so they show the same way.
- Thumbnails load from `groups.attachment.download` when the row appears (the Bot Chat loads whole files for thumbnails too). Each file keeps its `attachment_id` as its id, so the 2 s room poll never reloads a thumbnail, and the open room keeps downloaded bytes in memory so scrolling back or opening a file does not fetch it again. A failed thumbnail keeps the placeholder; the tap still opens it.

### Opening a file

- Tap a thumbnail or chip: Crew downloads it (`room_id`, the message's `event_id`, `attachment_id`) and opens Quick Look, as a Bot Chat does; Quick Look offers Share and Save. A failure shows the existing "Can't Open Attachment" alert with the reason.
- A file in an unsent bubble opens from its local bytes.

### Members

- **This gateway's members** get the files with the message (images seen directly, documents as a path they can read), and answer in text as usual.
- **A member on another gateway**: Crew does not block the send (Desktop doesn't); that member's turn fails visibly as the existing error row under its name with the server's reason, and the other members answer. Not reproducible live here (RoomLink is disabled on the test server), so it rests on the recorded `turn.failed` rendering.
- **A member posting a file**: not produced by Hermes 0.23.1, so not drawn in this change. When Hermes produces `message.member` attachments, they get leading-aligned thumbnails and chips under the reply (follow-up).

### Surfaces not touched

- Bot list: rooms have no preview, unread or status; only the "Draft:" line, which already counts attachments. Push: rooms have none. Room inspector: unchanged. Bot Chats: unchanged (the shared views take a download source; the Bot Chat's stays `/api/fs/download`).
- Light and dark, iPhone and Mac: the Bot Chat's views and system materials, nothing new to measure.
- Long content: long file names truncate in the middle on one line; eight images scroll in the row.
- Accessibility: thumbnails are labelled with the file name, chips read the name, the tray's remove buttons read "Remove <name>" (existing).

## Verification

- Unit tests over a recorded `crew-test` room (`Tests/chat_probe/run.sh room-files`: a throwaway room with crew-test, an image and a text file with a code word sent through `GroupSession.send`, crew-test's answer names the word and the colour, both files downloaded back byte-identical; writes `Tests/fixtures/rooms/files.*.json`): the manifest `groups.send` sends, the transcript turn's files, the download parameters, and the room tray limits.
- Renders: `group-chat-files` (a sent image and PDF, a pending tray) on iOS and Mac, light and dark.
- iOS UI: `ComposerUITests` on a private simulator (shared composer).
