# Rooms: members after creation (#113)

The issue asks to add and remove members of an existing room from its inspector, and to list a bot's rooms in its inspector, "using Hermes' groups RPCs". Checked against Hermes v0.23.1 (the server's release, `b65acf3`), the first half has no server support.

## What the server has (Hermes v0.23.1 source, not live-verified)

- **No membership verb.** The gateway's room methods are `groups.capabilities`, `list`, `create`, `state`, `send`, `rename`, `context`, `log`, `disband`, `stop`, `continue`, `retry`, `discard`, `approve`, `replicate`, `replica_state`, `promote`, `demote`, `peer.invite`, `peer.revoke`, `peer.register` and `attachment.upload`/`download` (`tui_gateway/methods_groups.py`, same list in `apps/shared/src/gateway-contract.generated.ts`). None edits the roster.
- **The roster is fixed at create.** `hosted_rooms.create_room` stores `members_json` once; calling `groups.create` again with the same `room_id` and a different roster raises `RoomConflictError("room_id already exists with different state")`. The only other write of `members_json` is a legacy room's adoption, which must carry the same members. `room.members_changed` is an allowed system event kind, but nothing at the tag emits it.
- **`groups.peer.invite`/`register`** mint and register a grant for a member that already sits on the roster on another gateway (cross-gateway rooms). They seat no one new, and Crew has one server.
- **Hermes Desktop.** Its gateway-owned rooms doc (`apps/desktop/docs/canonical-groups.md`) ends: "Membership editing is not offered." Desktop's Manage members (room) and Manage groups (bot) exist only for its older Desktop-driven rooms, whose roster lives in each bot's `ui_meta` `groups[]` and which Desktop itself runs (`group-chat-view-members.tsx`, `group-membership.ts`). Crew shows only gateway rooms (PLAN.md "Group rooms"), so those rooms and their editor are out of reach.

## Decision: no add or remove (Desktop parity)

Crew offers no way to change a room's members, as Hermes Desktop does for gateway rooms. Removing a member's threads, a removed Lead, the last member, swipe/Edit/context-menu removal and an add picker are all moot until Hermes ships a verb; this spec designs none of them.

- **New Room** keeps its footer "Pick 2 to 6 bots. Members can't change after the room is created." (still true).
- **Room inspector, Members section** gets the same fact as a footer, so someone looking for Add finds the answer where they look: "Members can't change after the room is created." No other change.
- **Rejected:**
  - Disband and recreate with the new roster: loses the room's history, its threads and every member's hidden room session, and changes the room's id under routines that post into it.
  - Writing Desktop's `ui_meta` `groups[]`: makes a Desktop-driven room that Crew can't show and only a running Desktop can drive.
- **Proposed PLAN.md Decisions line** (known limitation): "Room members are fixed (#113): Hermes v0.23.1 has no verb that edits a gateway room's roster (`groups.create` refuses a changed roster for an existing `room_id`) and Desktop offers no membership editing for gateway rooms, so Crew offers none; the New Room and room inspector footers say so. Revisit when Hermes ships one (a `room.members_changed` event kind is reserved)."

## Still shippable: a bot's Rooms (read only, needs go-ahead)

The issue's second half needs no new verb: `GroupStore.rooms` (from `groups.list`, every 10 s while supported) already carries each room's members.

- **Bot inspector, Info tab** (iPhone pushed page, Mac inspector column): a "Rooms" section after Other Conversations and before Delete Bot. One row per room whose members include this bot (`member.profile == bot.name`, the room inspector's match), in the sidebar's room order: `GroupAvatar` (28 pt, the size of the room inspector's member avatars) and the room name. A tap selects that room and closes the Mac inspector, mirroring the room inspector's member rows, which select the bot.
- **Empty:** no rooms, or the gateway doesn't support rooms: the section is hidden (Contacts hides empty fields; nothing to act on).
- **Offline:** shows the last list `GroupStore` holds; rows stay tappable (the room opens with its own offline state).
- **A room disbanded elsewhere:** drops out on the next `groups.list`.
- **Hidden bot:** its inspector (reached from the Hidden section) lists its rooms like any other; hiding is a UI filter.
- **Deleted bot:** has no inspector. Its rooms keep it as a roster row with the stored display name, as today.
- **Long content:** room names truncate to one line; a bot in many rooms gives a long section, no cap.
- **Light/dark, iPhone/Mac:** system `Form` rows, nothing custom. Renders: iPhone light and dark of a bot in two rooms and of the room inspector's new footer (the Mac is locked tonight, so Mac renders would come out blank).
- **Not done:** Desktop's per-bot Manage groups toggles (same missing verb).
