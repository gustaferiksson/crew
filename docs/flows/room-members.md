# Rooms: members after creation (#113)

The issue asks to add and remove members of an existing room from its inspector, and to list a bot's rooms in its inspector, "using Hermes' groups RPCs". Checked against Hermes v0.23.1 (the server's release, `b65acf3`), the first half has no server support.

## What the server has (Hermes v0.23.1 source; the method list matches the live `groups.capabilities`)

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
- **PLAN.md** records this as a known limitation (Decisions, "Room members are fixed").

## A bot's Rooms (read only)

The issue's second half needs no new verb: `GroupStore.rooms` (from `groups.list`, every 10 s while supported) already carries each room's members.

- **Bot inspector, Info tab** (iPhone pushed page, Mac inspector column): a "Rooms" section after Connections and before Other Conversations. One row per room with a member whose `profile` is this bot's name and which is not a peer (`target.kind == "peer"` is a namesake on another gateway, not this bot), in `groups.list` order (the sidebar's room order): `GroupAvatar` (28 pt, like the room inspector's member avatars), the room name, and a secondary line with the other members ("with Ada and Bo", roster titles, else the stored display name).
- **Tap:** selects that room, mirroring the room inspector's member rows (`isPresented = false`, then `select`). On iPhone the pushed page pops and the room replaces the bot in the detail; Back then returns to the list, not to the bot. On the Mac the inspector closes and the room opens in the main window. Rows follow PLAN's inspector rows: a tertiary chevron on the Mac, `.tint(.primary)` button rows on iOS.
- **Mac chat window** (`BotChatWindow`): its inspector shows the same rows without a button or chevron, since rooms stay out of chat windows (PLAN "Chat windows on macOS") and the window has no selection.
- **VoiceOver:** one element per row, labelled with the room name (a button where tappable), the other members as its value; the avatar is hidden.
- **Empty:** no rooms, or the gateway doesn't support rooms: the section is hidden (Contacts hides empty fields; nothing to act on).
- **Offline:** shows the last list `GroupStore` holds; rows stay tappable (the room opens with its own offline state).
- **A room disbanded elsewhere:** drops out on the next `groups.list`.
- **Hidden bot:** its inspector (reached from the Hidden section) lists its rooms like any other; hiding is a UI filter.
- **Deleted bot:** has no inspector. Its rooms keep it as a roster row with the stored display name, as today.
- **Long content:** names and the members line truncate to one line; a bot in many rooms gives a long section, no cap.
- **Light/dark, iPhone/Mac:** system `Form` rows, nothing custom.

## Verification

- `Tests/chat_probe/run.sh room-list`: two throwaway bots and three throwaway rooms (crew-test with each, and the two together), records `groups.capabilities` and `groups.list` to `Tests/fixtures/rooms/`, then disbands the rooms and deletes the bots. The recorded capabilities confirm the method list above on the live server.
- `BotRoomsTests` replays the list: crew-test sits in two of three rooms in server order, a peer namesake is excluded, and a server without rooms lists none.
- iPhone renders, light and dark: `inspector-rooms` (the section alone, ada in two rooms) and `group-inspector-members` (the room inspector without room settings, so Members and its footer fit on screen). No Mac renders: the Mac was locked, so they would come out blank.
