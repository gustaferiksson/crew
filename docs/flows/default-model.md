# Default Model: bots that follow the server's model

Crew bots each pin a model in their own profile (`profiles.configure {model, provider}`). New Bot already offers "Server Default" (it sends nothing, so Hermes copies the launch profile's model once at create). This adds the same choice to an existing bot and one "Default Model" setting per server that the following bots use. Bots with their own model keep it.

## What Hermes 0.23.4 does (source: hermes-agent 8fc0374, Desktop `plugins/hermes-bots/model-picker.tsx`)

- Desktop's "gateway default" is the picker's `NONE = '__default__'` value (provider and model both empty; label "Inherit (launch profile)", placeholder "gateway default"). Saving it (`profile-config.tsx` `applyAdvancedConfig`) calls `cli.exec {argv: ['--profile', <bot>, 'config', 'unset', 'model']}` and treats `blocked !== true && code === 0` as success. `profiles.configure` cannot clear the model: `_configure_model` returns without writing unless both model and provider are non-empty. A half-filled pair is refused client-side.
- A bot with no `model` in its config.yaml does not live-follow another profile. `_resolve_model` (tui_gateway/agent_factory.py) uses the process env seed (`HERMES_MODEL`, `HERMES_INFERENCE_MODEL`) if set, else the cache-only "silent default" (`get_preferred_silent_default_model`, a cost-safe model, not the default profile's). The only inheritance code is `inherit_launch_model` (profile_provision.py), a one-time copy at create. The Bot Mode doc's "leave it unset to inherit from the launch profile" therefore means that copy.
- The gateway default is the launch profile's (`default`, `is_default: true`) config.yaml `model`. Desktop sets it from Settings > Model with `POST /api/model/set {scope: "main", provider, model, confirm_expensive_model?}` (may answer `confirm_required`). Over the gateway socket the same write is `profiles.configure {name: <default profile>, model, provider}`, which Crew's `changeModel` already sends. No dedicated "default model" verb exists, and Desktop's Bot Mode UI exposes it nowhere (the default bot is just a bot there).
- Open (unverified on a server): what a session of a bot with the model unset reports in `session.info.model` and `model.options.current`. Phase 2 probes this on `crew-test` first (`config unset model`, then `profiles.list`, `model.options`, a prompt's `session.info`).

## Decision gate

- **A, Desktop-identical:** "Server Default" runs the same `cli.exec ... config unset model`. The bot then runs the env seed or silent default, not the Default Model. Honest only if the probe shows it resolves to the default profile's model (a server with `HERMES_MODEL` set to it, say).
- **B, Crew follows (recommended if the probe shows A does not follow):** "Server Default" pins the bot to the current default model (`changeModel`) and sets `ui_meta["crew"].followsDefault = true` (CAS on the revision, merged with the read marker). Changing Default Model writes the default profile, then re-pins every bot with the flag (one `profiles.configure` each, sequential, `confirm_expensive_model` only after the user's confirm). Any manual model pick on a bot clears the flag. Limit: bots re-pin only while a Crew client does the change; the sheet says "N bots follow it" and a failure names the bots that kept the old model. Unset/pinned state is always what Hermes sees, so Desktop and the CLI stay correct.
- Either way the Default Model write is `changeModel` on the default profile, so it also changes the Default bot's own model (the same file in Hermes).

## Surfaces

Model rows list "Server Default" first (checkmark when the bot follows, subtitle with the current default model name, e.g. "Server Default · gpt-6-astra"), then the providers and models from `model.options`. A bot's own pick shows its model name as today.

- **Inspector, Info > Model** (iPhone push page and Mac inspector column): the existing menu gains the row first in the inline picker. Spinner while saving, alert with Hermes' message on failure, "Use This Model?" confirm unchanged. For the Default bot the row is absent (it is the default).
- **Chat toolbar** (persona pill context menu, iPhone and Mac): same `ModelPicker`, "Server Default" first, checked by the same state as the inspector (they share one `ModelSwitcher`).
- **New Bot > Advanced:** already has "Server Default" (nothing sent at create; Hermes copies the launch model). Under B it also sets the follow flag; the footer reads "Follows the default model." Duplicate keeps "Same as <source>".
- **Settings (Mac), Server section:** "Default Model" row (a pop-up menu like the inspector's, current model name or "Not set") with footer "Bots set to Server Default use this. Bots with their own model keep it." Changing it asks the usual expensive-model confirm.
- **iPhone:** Crew has no Settings screen; the row goes with Sign Out in BotsView's account menu as "Default Model", pushing a one-row Form (same menu, same footer). Both surfaces share one store call.
- Bot list (preview, time, status, unread), push and rooms are unaffected: no message is sent when the model changes.

## States

- Loading: the row shows the current default name (from `profiles.list`, no extra call) with the menu disabled until `model.options` arrives, as the inspector does.
- Empty: `model.options` empty or failed: rows show text only (no menu), Server Default is not offered (it needs a choice to exist to make sense).
- Error: alert with Hermes' message ("The server didn't change the model." fallback); the row snaps back to the previous value. Under B a partial fan-out reports "Default model changed. N bots kept the old one: names" and leaves their flag set, so a retry from the same menu re-applies.
- Offline or reconnecting: menus disabled (`connection.state != .connected`), values keep what loaded.
- Long names: model ids and bot names truncate in the middle on one line in rows, menus and the confirm alert; footers wrap.
- Light and dark: system Form and Menu styling only, no custom colors. Mac Settings width unchanged; the iPhone page is a standard grouped Form (Dynamic Type safe).
- Server without `cli.exec` or with it blocked (`blocked: true`): under A the row is hidden; under B it is unaffected.

## Out of scope

Reasoning effort, auxiliary models, per-chat session model, and anything but the main model.

## Tests (Phase 2)

Real-server probe on `crew-test` plus throwaway `crew-test-*` bots only (never the `default` profile on a real server: setting it is a config change, so the Default Model write is tested against `Tests/fixtures/fake_gateway.py`). Unit: the follow-flag fan-out and failure reporting from recorded `profiles.configure` replies; the marker CAS merge.
