# Development process (as practised, October 2026)

This describes how changes to Crew actually get made today, including what goes wrong, as input for a later redesign toward a streamlined issue-to-PR "software factory". It is descriptive, not a proposal. Numbers come from GitHub (`gh` issues, PRs, Actions runs and jobs) for 17 and 18 October 2026, PRs #61 to #82. Times are UTC. Rules live in `CLAUDE.md` (local, not in the public repo), `docs/PLAN.md`, `docs/release.md` > Development flow and `Tests/README.md`; this file summarizes them rather than replacing them.

## Roles

| Role | Who | Does | Does not |
| --- | --- | --- | --- |
| Product owner | The user, often on a phone | Reports bugs and wishes in chat or as issues, answers questions asked through the session's question prompt, approves permission prompts (deploys, force pushes, closing things), decides irreversible picks (which real card to delete, server config) | Write code, run shell commands, approve specs (specs are reviewed by an agent, not the user) |
| Orchestrator | The main Claude session | Turns reports into agent prompts, keeps few agents in parallel, checks renders and `gh pr checks`, merges, tags releases, deploys crew-push, files follow-up issues, keeps the local handover note | Implement features itself (the user corrects this when it happens) |
| Implementer | One Opus subagent per issue, in its own git worktree under `.claude/worktrees/` | Branch, flow spec, code, tests, renders, `./build.sh`, PR, fixes from review | Merge, deploy, act on a permission denial (it reports it instead) |
| Research agent | Read-only subagent | Root-causes against the real server, Hermes source and logs before a fix is built | Write code |
| Spec reviewer | A separate agent, before code | Checks the flow spec for completeness (every surface, direction and state) and HIG fit | Write code |
| User-side reviewer | A separate agent, before merge | Uses the change "from the user's side": reads the diff, renders and tests, reports findings the implementer then fixes | Leave a GitHub review (0 of 19 PRs have one, see below) |

Model choice is fixed by the user: Opus (or Fable) only, never smaller models. Who spawns the reviewers varies: in one session's account the implementer spawns its own spec and user-side reviewers; in another the orchestrator does. Nothing records which happened for a given PR.

## Pipeline, step by step

| # | Step | Who | Tooling | Gate |
| --- | --- | --- | --- | --- |
| 1 | Report | User | Chat message or GitHub issue | None; most reports arrive in chat |
| 2 | Agent prompt | Orchestrator | Free-form prompt, rules restated each time | None; no shared template |
| 3 | Branch and worktree | Implementer | `git switch -c <name>` in an isolated worktree | One branch per change |
| 4 | Flow spec | Implementer | `docs/flows/<feature>.md` | Spec reviewer agent |
| 5 | Code | Implementer | SwiftUI app, crew-push Python plugin | |
| 6 | Tests | Implementer | Unit and scenario replay, iOS simulator UI tests, macOS UI tests (CI only), pytest | Local runs, then CI |
| 7 | Renders | Implementer | `./snapshot.sh` / `-snapshot <screen>`, light and dark | Orchestrator looks at them |
| 8 | Build | Implementer | `./build.sh`, zero warnings | Build fails on any warning |
| 9 | PR | Implementer | `gh pr create`, never `--draft` | |
| 10 | CI | GitHub Actions | `ci.yml` | `gh pr checks` green |
| 11 | Independent review | Reviewer agent | Diff, renders, tests | Findings fixed and pushed |
| 12 | Final check | Orchestrator | Renders, `gh pr checks` as a standalone command | |
| 13 | Merge | Orchestrator | `gh pr merge N --squash --delete-branch` | Green checks |
| 14 | Release | Orchestrator | `git tag v0.1.x`, release workflow | A merged feature whose PR CI passed (main's CI is not awaited again) |
| 15 | Deploy crew-push | Orchestrator (or user) | rsync to the server, then ssh chown and service restart | Two exact-match allow rules |
| 16 | Real-server check | Orchestrator or agent | Probes on `crew-test`, version and journal check | |

### 1 to 3: from report to worktree

A report is usually a chat message, often a screenshot from the phone ("tapping a notification crashes on iPhone"); sometimes it is filed first as an issue, especially follow-ups the orchestrator records while the user is busy. Of the 21 PRs #61 to #82, 10 close an issue; the four open PRs (#78 to #81) close none, because they came straight from chat. Issues have no template and no acceptance criteria field.

The orchestrator writes the subagent's prompt by hand. Every prompt repeats the same guardrails (crew-test only, no draft PRs, force-with-lease allowed on the branch, report denials, private simulator) because there is no single prompt template. Each implementer starts with no memory of earlier agents; what it knows is the prompt, `CLAUDE.md`, `docs/PLAN.md` and the flow specs.

### 4: flow spec and spec review

Features start with a short `docs/flows/<feature>.md` listing every surface touched (each chat, the bot-list row's preview, time, status and unread, push, inspector, iPhone and Mac, light and dark), every direction (sender, receiver, replies back) and the empty, error, offline and long-content states, judged by "what would Apple do". A separate reviewer agent checks it before any code. The user does not approve specs. 15 of the 21 PRs touched a flow spec; the ones without are flake fixes (#76, #77, #82), a CI probe (#65) and a five-line crash fix (#79).

### 5 to 8: code, tests, renders, build

- **Unit and scenario replay** (`Tests/CrewTests`): a scenario is a real flow recorded once from the server on `crew-test` (plus throwaway `crew-test-*` bots) into `Tests/fixtures/scenarios/`, scrubbed, then replayed offline through `BotStore` and the transcript code to assert what each surface shows. This is the main behavioural proof and runs locally in seconds.
- **iOS UI tests** (`Tests/CrewUITests`, `Tests/ui.sh`): each run creates its own simulator (`crew-ui-<pid>`) and deletes it on exit, because parallel agents would otherwise fight over the shared default simulator. The app launches with `-snapshot <fixture>` and never touches the network.
- **macOS UI tests** (`Tests/CrewMacUITests`): they drive real windows, which is never allowed on the user's Mac, so they run only on a CI runner. An agent writing a Mac UI test cannot run it before pushing.
- **crew-push**: pytest in `server/crew-push/tests`, plus scenario cases replaying the same recorded rows.
- **Renders**: only for new or changed visuals. iOS via `simctl` on a private simulator; macOS via the app's `-snapshot` mode, an offscreen window captured to PNG. Mac captures come out blank while the Mac display is locked or asleep, which is often the case when the user is away. Renders that matter are committed under `docs/flows/renders/` (80 files, 19 MB so far).
- **Build**: `./build.sh` (XcodeGen plus xcodebuild, macOS and iOS Simulator) must finish with zero warnings.

### 9 to 13: PR, CI, review, merge

PRs are always regular PRs. Drafts are banned since #71: an agent opened it as a draft, could not mark it ready (`gh pr ready` was denied), and it was closed and replaced by #74 the next morning.

CI (`.github/workflows/ci.yml`) on every PR and push to `main`:

| Job | Runner | Runs when | Median run (after #63) |
| --- | --- | --- | --- |
| Detect app changes | ubuntu | always | 0.1 min |
| crew-push tests (version strings agree, skill frontmatter, pytest) | ubuntu | always | 0.3 min |
| Build macOS and iOS (unsigned): `./build.sh`, UI test bundle, unit tests | xcode-27 | app paths changed | 4.7 min |
| UI tests (iOS Simulator, composer shard) | xcode-27 | app paths changed | 12.2 min |
| UI tests (iOS Simulator, rest shard) | xcode-27 | app paths changed | 14.4 min |
| UI tests (macOS) | xcode-27 | app paths changed | 3.8 min |

The path filter skips the four macOS jobs when a change touches only `docs/`, `server/crew-push/` or Markdown outside `Sources/` and `Tests/fixtures/`. The iOS shards boot their simulator while the app job builds, then download its build. #63 (merged 17 Oct 20:10) introduced the filter and the shards: whole runs went from 22 to 38 min before it to roughly 13 to 28 min after, when runners are free. There is no `concurrency:` group, so a superseded push keeps its run going. Branch protection on `main` requires only two checks, "Build macOS and iOS (unsigned)" and "crew-push tests", enforced for admins too; the three UI test jobs are not required, so waiting for them is the orchestrator's discipline, not a GitHub gate.

After CI, a reviewer agent uses the change from the user's side and reports to the orchestrator; the implementer fixes and pushes. This review happens in agent transcripts only: of 19 PRs sampled, none has a GitHub review or comment, and 8 mention a review in the PR body. The orchestrator then looks at the renders, runs `gh pr checks` as a standalone command, and squash merges.

### 14 to 16: release, deploy, verify

The orchestrator tags the next `v0.1.x` right after a merge whose PR CI passed. 24 releases went out in 5 days (v0.1.0 on 14 Oct to v0.1.24 on 18 Oct), five of them on 18 Oct. The tag workflow builds the notarized Mac zip, the Ad Hoc IPA, the GitHub Pages OTA manifest and the crew-push tarball (`docs/release.md`).

crew-push is deployed separately when its version changes: rsync of `server/crew-push/` (without tests and caches) to the plugin directory on the server, then one ssh command that fixes ownership and restarts the Hermes service, then a check of the plugin version and the service journal. Both commands are exact-match allow rules, so they run as two separate calls. Then the flow is verified on the real server on `crew-test`. Finally the user gets `./device.sh` on the iPhone and a rebuilt Mac app.

## Guardrails

- **Mutations only on `crew-test`** and throwaway `crew-test-*` bots (created via `profiles.create` if missing, deleted on every path). All other profiles are read-only. Never install plugins, restart or change server config without the user, except the allow-listed crew-push deploy.
- **No real bot prompts unless essential.** Each prompt costs the user model usage, so recorded fixtures replace live prompting wherever possible.
- **Secrets**: `.env.test` holds the server credentials; never printed, logged, committed or copied. Scenario recordings scrub the host, the user and throwaway names.
- **Public repo**: no server details, real names or personal content in commits, fixtures, renders or docs. The initial publish was a fresh history after a gitleaks pass (`docs/release.md` > Audit result).
- **Defaults domain**: never write to or delete `dev.gustaf.crew` (Debug and release Mac builds share it).
- **Never drive Mac windows or focus.** Mac interaction tests run only on CI; Mac renders use the offscreen `-snapshot` mode.
- **Git identity**: plain `git commit`, never an author or committer override; if identity is missing, stop.
- **History**: `main` moves only through squash-merged PRs. Feature branches may be rebased and pushed with `--force-with-lease`, never `main`. If a force push is denied, push a new branch and replace the PR.
- **Permissions (auto mode)**: a classifier allows or denies each command. Denied for agents at various points: `gh pr ready`, `rm -rf`, setting `GIT_EDITOR`, force pushes, the crew-push deploy, closing PRs and issues, any edit to settings files, and compound shell commands it cannot verify (this document's own data gathering was refused once for a loop with a computed command inside a worktree). Fixes so far: project-local allow rules for `gh pr merge/checks/ready/edit/close`, `gh issue close`, `git push --force-with-lease*` and the two deploy commands. Rule for agents: a denial is reported, not worked around. The orchestrator then runs the command itself so the user sees and approves the prompt (often from a phone), rather than handing the user a command to type.
- **Locked UI values**: the "UI values (locked)" block in `docs/PLAN.md` changes only on a user request, which stopped agents re-deciding separators, bubbles and the composer from one PR to the next.
- **Hands-off**: the user wants to be as hands-off as possible; the orchestrator decides, merges and releases on its own terms and asks only for destructive or irreversible choices.

## Measured pain points

### Lead time per PR

Open to merge, wall clock. "Active" excludes the overnight gap between the last green run in the evening and the morning session.

| PR | What | Open to merge | Active | CI runs | Red runs | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| #61 | crew-push 0.4.1 | 0.4 h | 0.4 h | 1 | 0 | |
| #63 | CI speed-up | 4.4 h | 4.4 h | 8 | 0 | plus #65, a PR opened only to probe the path filter |
| #64 | crew-push 0.4.2 | 0.9 h | 0.9 h | 2 | 0 | |
| #66 | crew-push 0.4.3 | 0.4 h | 0.4 h | 1 | 0 | |
| #67 | crew-push 0.4.4 | 0.5 h | 0.5 h | 1 | 0 | |
| #68 | unread after clear | 9.8 h | about 1.6 h | 4 | 2 | one manual re-run |
| #69 | Mac reply selection | 10.9 h | about 1.8 h | 4 | 0 | rebased in the morning |
| #72 | card window height | 9.1 h | about 0.7 h | 2 | 0 | |
| #73 | add master card | 9.9 h | about 1.5 h | 4 | 2 | own new UI test failed twice |
| #71 / #74 | Mac chat window | 12.3 h (first open to merge) | about 3 h | 2 + 5 | 2 | draft stranded, replaced; 2 force pushes |
| #75 | Passwords tab (1843 lines added) | 1.9 h | 1.9 h | 1 | 0 | |
| #76, #77, #82 | flake fixes | 0.0 to 0.4 h | same | 1 each | 0 | exist only because of flakes |
| #78 to #81 | four fixes in parallel | open after 1 h+ | | 2 to 5 each | 1 or 2 each | still open at time of writing |

Small crew-push and flake PRs merge in under an hour. App features take 1 to 3 active hours and, when they finish late, sit overnight because merging waits for the orchestrator session. The 10-hour figures are idle time, not work.

### CI runs and failures

From 17 Oct 20:33 (after #63) to 18 Oct 13:20: 37 PR runs, about 10 of them red (27 %). Main went red on 2 of 10 pushes, both flakes. The 17 failed jobs break down as:

| Cause | Failed jobs | Examples |
| --- | --- | --- |
| Flake in a test unrelated to the PR | 8 | in-app browser waits for Safari's remote UI (#74, main); steer split timing (#73); "Failed to terminate" the app (#68); the crew-push card-leak test matching `321` inside a timestamp (#79, main); a Passwords UI tap (#79, a five-line crash fix) |
| A new test the PR itself added, failing on CI | 6 | Mac chat window double-click (#74, twice); add-card UI test (#73, three jobs in two runs); Mac steer bubble (#80, twice). Mac UI tests cannot run before push, so each attempt is a CI round trip |
| Real defect caught by CI | 1 | crew-push version strings out of sync (#78) |
| Unclear from logs | 2 | iOS rest shard "TEST EXECUTE FAILED" (#79, #81) |

Three PRs in one day (#76, #77, #82) were spent only on flakes. A red run on an unrelated flake costs a re-run of 15 to 45 minutes.

### Conflict hotspots

Several PRs in flight at once all edit the same few files, so whichever merges first forces the others to rebase. Of 19 PRs sampled:

| File | PRs touching it | Why |
| --- | --- | --- |
| `Sources/Snapshot.swift` | 8 | every new render screen adds a fixture case |
| `snapshot.sh` | 7 | the `ALL` screen list is one long line |
| `docs/PLAN.md` | 8 | every decision is a line in one Decisions list |
| `server/crew-push/plugin.yaml` (and the three other version strings) | 8 | every crew-push change bumps the version; two parallel PRs (#78, #81) both claim 0.6.1 |
| `Tests/CrewUITests` | 8 | |

Force pushes after rebases: #74 twice, #78 and #79 once each. #69 and #73 were rebased and re-run in the morning after the evening's merges, adding one full CI run each.

### CI capacity and queueing

Runners are fine with one PR at a time (median queue under 1 minute). With four PRs pushed between 12:13 and 12:27 on 18 Oct, each needing four macOS jobs, the build job queued up to 33.5 minutes and UI shards up to 28.6 minutes; whole runs then took 45 to 52 minutes instead of about 20. At most 9 macOS jobs were seen running at once. #79 pushed three times within three minutes, and with no concurrency group all three runs competed for the same runners.

### Permissions that needed the user

Not measurable from GitHub, observed in the sessions: the stranded draft (#71 to #74, about 10 hours lost, user had to intervene), denied force pushes and deploys before the allow rules existed, settings edits that stay blocked, and issue/PR closes. Each needed the user to approve a prompt, sometimes from a phone, or blocked an agent until the orchestrator re-ran the command.

### Stacked PRs and server surprises

- Deleting a merged PR's base branch (`--delete-branch`) closed the PRs stacked on it; two payment PRs had to be reopened. The practice since is to retarget dependents before merging the base.
- The real server differed from what specs assumed (Browser Use mode exposing only `browser_exec`, `browser_exec` gated on the terminal tool, the model ignoring plugin text), which cost several crew-push redeploys (0.4.1 to 0.4.4 in one afternoon). A research agent against the real server before building is now the habit, not a rule.

### Agent environment limits

- Mac `-snapshot` captures are blank whenever the Mac display is locked or asleep, so Mac visuals often can't be checked when the user is away.
- Mac UI tests run only on CI (see above).
- Real bot prompts are avoided for cost, so end-to-end checks of model behaviour wait for the user.
- Agents share one iOS default simulator unless they create their own; `Tests/ui.sh` and the render scripts now create private ones.

### Context lost between agents

Each implementer and reviewer starts fresh. Shared context is the prompt, the repo docs and a local handover note that only the orchestrator maintains. The same rules are restated in every prompt, and rules learned from an incident (no drafts, force-with-lease is fine) exist only in the orchestrator's saved notes until copied into the next prompt. Reviewer findings live in transcripts, so the next agent on the same area doesn't see them. The orchestrator itself is one long session: over several days its context grew until it was slow, compacted and noisy with agent notifications, and it was handed over to a fresh session through the handover note.

### Scratchpad and worktree debris

All subagents of one session share one scratchpad directory. By the afternoon of 18 Oct it held 141 entries, with names like `build.log`, `build0.log` to `build4.log`, `before`, `after` and `dump.log` from different agents, so one agent's file can overwrite or be mistaken for another's. 21 agent worktrees were still present under `.claude/worktrees/`.

## What a factory would need (gaps, not a design)

- **Issue intake**: an issue template with acceptance criteria, surfaces, platforms and states, so the flow spec starts from the issue and every PR closes one (today 10 of 21 do).
- **One agent prompt template** holding the guardrails, test and render expectations and PR rules, versioned in the repo, instead of rules restated by hand.
- **Queue and concurrency limits**: how many implementers run at once, and which issues may run in parallel given shared files.
- **Conflict hotspots designed out**: per-screen snapshot registration instead of one switch and one list, a Decisions log that does not need every PR to edit the same block, and a crew-push version bump at release rather than per PR.
- **CI capacity**: a `concurrency` group that cancels superseded runs, a budget for parallel macOS jobs, and quarantine or retry for known flaky UI tests so unrelated flakes stop blocking merges.
- **A way to run Mac UI tests before push**, or an accepted cost for iterating on them in CI.
- **Permission model**: an explicit list of what agents may do unattended (merge, tag, deploy, force-with-lease, close) versus what needs the user, set up front instead of discovered by denial.
- **Verification artifacts on the PR**: spec link, spec review verdict, renders, test summary, real-server probe result and the user-side review as PR comments or a check, so merge decisions don't depend on agent transcripts.
- **Shared state hygiene**: per-agent scratch directories, worktree and simulator cleanup, and a persistent handover that any agent can read.
- **Required checks that match the merge rule**: the UI shards are not required on `main` today.
- **A device loop**: getting a build onto the phone for the user to test without cutting a release.
- **Metrics**: user-reported bugs after merge, CI minutes, and time from ask to release, per feature, so a factory can show it is improving. None are tracked today; this document's numbers were gathered by hand.
- **Merge without the orchestrator present**, so green, reviewed PRs don't wait overnight.

## Where the two sessions' accounts diverge

The previous orchestrating session wrote its own account; it agrees with this one on the pipeline and guardrails. Differences:

- It has the implementer spawn its own reviewers; this session's agents were usually reviewed by agents the orchestrator spawned.
- It treats real-server probes as "only when the feature truly needs it"; `CLAUDE.md` asks for probes of the full flow in every direction. In practice the cost rule wins.
- It records the CI speed-up as "required build check about 4 minutes"; that is true for the gate, but a PR is only judged green after the UI shards, which take 12 to 15 minutes alone and up to 50 minutes under load.
- It lists stacked-PR breakage and server surprises as the costly failures; this session's data adds flakes, hotspot rebases and runner queueing, which dominated 18 October.
