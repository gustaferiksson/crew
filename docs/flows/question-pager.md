# Question card: one question at a time

Hermes' `clarify` tool asks 1 to 5 questions in one server request. Each question is a single choice (up to 4 `choices`), a multi-select (`multi_select: true`) or free text (no `choices`). Today `QuestionCard` stacks every question in one tall card and draws radio circles even for a multi-select. New: a compact pager that shows one question at a time and sends every answer together at the end, with checkboxes for multi-select and a badge for the recommended option.

## Payload (Hermes `tools/clarify_tool.py`, `tui_gateway/contracts/server_requests.py`)

- `params.questions[]`: `qid` (`q0`, `q1`, …, the answer key), `question`, `choices` (null for free text), `multi_select` (bool, false when there are no choices).
- "(Recommended)": there is no flag. The server appends the literal suffix ` (Recommended)` to the first choice of any question with 2 or more choices, multi-select included, and strips it again from answers (`strip_recommended`).
- Reply: `{answers: {qid: text}}` for the whole set; `{}` cancels all (Skip). A multi-select answer is a JSON array string (`["Chips","Fruit"]`), exactly what Hermes' own TUI sends; a single choice or free text is the plain text.

## The card

- **Header:** "<Bot> has a question" as today. With 2 or more questions it gains "1 of 3" trailing in the header row (footnote, secondary, monospaced digits). VoiceOver reads it as "Question 1 of 3".
- **Body:** the current question's text, then its options or text field. Only the current question is in the hierarchy, so the card is as tall as one question.
- **Single choice:** bordered rows (neutral, the picked one accent-tinted) with a radio indicator (`circle` / `checkmark.circle.fill`) as today; one pick. Choosing it on any step but the last moves to the next step after a short beat (0.3 s, so the check is seen), like the iOS setup flows; on the last step it only selects (sending stays a deliberate tap). With VoiceOver or Switch Control on it never auto-advances, so the pick is heard first and Next moves on.
- **Multi-select:** checkbox indicators (`square` / `checkmark.square.fill`); each tap toggles; several picks allowed; never auto-advances. Picks are sent in the order of the choices, not the tap order. Picking none is a valid answer ("none of these"): Next stays enabled and the qid is sent as `""`, exactly what Hermes' TUI sends, which the server records as `skipped`.
- **Recommended:** the suffix is removed from the label and shown as a small "Recommended" capsule (caption2, secondary, tertiary fill) trailing the option. The answer sent is the bare label (the server would strip it anyway). VoiceOver reads "Lake swim, Recommended".
- **Free text:** the plain field as today ("Your answer", 1 to 4 lines).
- Selected rows carry the `isSelected` trait.
- **Buttons:** one row, flexible capsules: Skip (bordered), Back (bordered, only from step 2), and Next (bordered prominent) or, on the last step, Send (prominent). Next and Send are disabled until the current single-choice or free-text question has an answer (a pick, or text that isn't only whitespace). Answers are kept when going Back and forward again. Skip cancels the whole set from any step (the label stays "Skip", as asked), discarding earlier answers; no confirmation, since nothing is lost on the server side and the bot can ask again.
- **Transition:** the body pushes from trailing on Next and from leading on Back (`.smooth`), a cross-fade under Reduce Motion; the card's height animates with it. The page is clipped horizontally only, so the rows' edges stay intact.
- **Keyboard (Mac):** the card takes keyboard focus when the user picks an option and on every step change (itself on choice steps, its text field on the free-text step), never on appear, so typing in the composer when a question arrives is not interrupted, and Return (without Shift) advances or sends via `onKeyPress`, the same pattern as the composer. No `.defaultAction` shortcut, because it would compete with the composer's own Return. Clicking into the composer moves focus there, and Return then belongs to the composer. Shift-Return in the field inserts a line. On iPhone the soft keyboard's Return inserts a line as today; a hardware keyboard's Return in the field advances. Unverified on a real Mac window (no window driving here); it rides the same `onKeyPress` path the composer already ships. Escape is not bound (Skip cancels the whole set, too heavy for a stray key).
- **VoiceOver:** on each step change focus moves to the question text, whose label starts with "Question 2 of 3", so the new question and its position are read together.
- **One question:** no "1 of 3", no Back; Skip and Send as today. Looks like today apart from checkboxes and the badge.

## Surfaces and directions

- **Chat (iPhone and Mac):** the card sits above the composer in the bottom bar, 560 pt max with 16 pt sides (locked UI values, unchanged). The layout code is one shared SwiftUI view; only the keyboard shortcut differs in effect per platform. Mac isn't rendered here (no window driving); iOS is rendered light and dark.
- **Sender (user) to bot:** the answers go in one `{answers}` reply on Send; Skip sends `{}`. Nothing else changes: the bot's turn resumes, the work log keeps its "Asked" row, the request leaves `openRequests`.
- **Bot list, push, inspector:** unchanged ("Waiting for you" status and the question push come from the server request, not the card).
- **Groups:** rooms surface no clarify questions (PLAN.md), unchanged.

## States

- **Offline:** the card stays usable as today; a reply that fails shows the chat's failure line, as today.
- **Payment request mid-pager or a failed reply:** a payment approval shows before the question card and a failed reply drops the card (both as before); the pager then starts again at step 1 (known gap: progress lives in the card).
- **Cancelled elsewhere** (`request.cancel`, answered on another device): the card leaves; local answers are dropped. The card is keyed by the request id, so a later clarify request starts fresh at step 1 (its `q0` keys never inherit old answers).
- **Long content:** a long question wraps; long choice labels wrap inside their rows; 4 choices plus the badge fit on iPhone because only one question shows. Large Dynamic Type grows the card; the transcript above shrinks as today. A pathological payload (choices up to 8000 characters) can still outgrow the screen; no inner scroll view yet (known gap, much smaller than today's stacked card).
- **Empty choices:** a question with no choices is free text (the server never sends an empty array).
- **Reconnect replay with locked `answers`:** not prefilled (known gap, as today).
- **"Other" free-text row:** Hermes' TUI appends one to every choice question; Crew doesn't (known gap, as today).

## Tests

- Unit (`QuestionCardTests`): decode the 3-question server request fixture (`Tests/fixtures/clarify.three-questions.json`): kinds, `multi_select`, recommended label stripped and flagged. Answer assembly: single choice text, multi-select JSON array in choice order, trimmed free text, unanswered questions block Send.
- UI (`QuestionCardUITests`, `-snapshot chat-questions`): step 1 of 3 picks an option and auto-advances, step 2 picks two snacks (checkbox values), Back keeps the first pick, step 3 types a name, Send logs the exact answers dict.
- Renders: `chat-questions` steps 1 and 2 and `chat-question` (one question), iOS light and dark.
