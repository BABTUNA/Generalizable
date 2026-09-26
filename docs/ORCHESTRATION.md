# Generalizable — agent orchestration (3-hour demo)

> **This is a hackathon DEMO with a 3-hour budget, not a product.** It uses public open-source research data (Visible Human, CQ500, Seg-CQ500). Nothing in it is a diagnosis. When a rule below slows you down more than it protects the demo, cut scope rather than skip the rule. The scope order is in PRD addendum **A7**.

This process is modelled on FlashTeX's orchestration. It keeps FlashTeX's Git + Markdown task board + handoff discipline and drops the rest: failover, budget ledgers, recovery queues and polling supervisors.

## Step 0: agent registration (mandatory)

**Every agent registers in `coordination/agents/<agent-id>.json` before it edits anything, and commits that file as its first commit.** The schema and rules are in `AGENTS.md`.

- Registration is how agents claim a lane. Two active registrations must never own overlapping paths.
- An agent that isn't registered is treated as not existing. Its changes aren't integrated.
- The Commander checks the registrations at every integration and marks stale ones.

## Read first

1. `docs/PRD.md`, especially the **Addenda** section: A1 (cut geometry), A2 (hinge mapping), A3 (SDK), A4 (bundle format, which is the contract), A5 (cases), A6 ruling, A7 (scope).
2. `coordination/TASKS.md`, to see who owns what.
3. Your lane's handoff in `coordination/handoffs/`.

## Roles

| Role | Who | May | May not |
|---|---|---|---|
| **Commander** | Daniel's Claude Code session | Edit `coordination/TASKS.md` and `COMMANDER.md`, add PRD addenda, integrate lanes, commit to the demo branch | Write lane code while a worker owns that lane |
| **Worker** | One agent per lane (Claude Code subagent, Codex, or Bitrig's agent) | Edit only the paths its lane owns, and write its own handoff | Edit another lane's paths, TASKS.md, or earlier PRD sections. Push to `main` |
| **Reviewer** | Fresh read-only agent | Read the diff, the contract and the check output, then report defects | See the worker's reasoning. Edit files |

Only the Commander writes control state. If the Commander session dies, Daniel names the next one; there's no automatic failover.

## Where things get built

**Most of the visualization is built in Bitrig, and the app runs from Bitrig.** That covers the SwiftUI views, the Metal rendering, device layouts and the hinge. Work outside Bitrig covers:

- data preparation (Python)
- the synthetic bundles
- small non-visual Swift pieces in `App/Core/` that Bitrig's agent calls into
- the planning and coordination documents

Anything outside Bitrig must reach Bitrig through git: push the demo branch, then pull it in Bitrig. Don't hand-edit views outside Bitrig while a Bitrig session is building them, because that causes merge conflicts in files Bitrig rewrites.

### How the pipeline changes in Bitrig

Bitrig is a different kind of worker from a terminal agent. The process adapts in these ways:

| Concern | Terminal agents (Claude Code / Codex) | Bitrig's agent |
|---|---|---|
| **Registration** | The agent writes its own JSON file | Each Bitrig session's **Prompt 0** tells it to update its pre-created file, `coordination/agents/bitrig-l3b.json` or `bitrig-l3c-duo.json` (status → `active`, model, branch), and commit it. The Commander pre-created both files with status `not-yet-registered`. |
| **Commits** | The Commander commits for in-session workers | Bitrig auto-commits (it authored the rename commit). **Point each Bitrig project at its own branch (`agent/bitrig/l3b` for account A, `agent/bitrig/l3c-duo` for account B), never `main`.** The Commander merges both into the demo branch. |
| **Handoff** | Written by the agent | Every Bitrig prompt ends with "update `coordination/handoffs/<your lane>.md` using the template in `docs/ORCHESTRATION.md`." Daniel checks it before the next prompt. |
| **Ownership** | Path rules | Bitrig rewrites files freely, so its paths are split hard. **L3b owns `Project.json`, `App/App.swift`, `App/ContentView.swift` and `App/UI/`. L3c owns `App/Render/` and `App/Duo/`.** The interface between them is `docs/contracts/render-interface.md`. |
| **Verification gate** | `xcrun swiftc -typecheck`, scripts | Bitrig's own build plus a run on its simulator, checked by eye against each prompt's acceptance line. There's no Duo simulator until the iOS 27.1 SDK is selected (A3). |
| **Data** | Local files | **Bitrig builds from the Git repo, so gitignored bundles never reach it.** Per the A8 ruling, the Commander runs `scripts/make_demo_bundles.py` to produce bundles with every file under 45 MB, and commits all four cases in `App/Cases/`. |
| **Sync** | `git pull` | New `App/Core` or bundle changes reach Bitrig only after the Commander pushes and Bitrig pulls. **Batch them: push at most every ~30 minutes** so Bitrig isn't rebuilding against a moving target. |
| **Scope of a turn** | Whole lane | One prompt of about 10–20 minutes from `docs/bitrig-prompts.md` at a time, with a run on the simulator between prompts. |

## Lanes and path ownership

Lanes must not share paths. If you need a change in a path you don't own, write it under "Blockers / requests" in your handoff. The Commander routes it.

| Lane | Owns | Contract it produces or consumes |
|---|---|---|
| **L1 data**: real CT bundles | `data/` except `data/synth/`, plus the `.gitignore` entries for `data/raw/` and `data/work/` | Produces A4 bundles in `data/out/body`, `data/out/brain` |
| **L2 synth**: Sun and Circuit board | `data/synth/`, `App/Cases/sun/`, `App/Cases/circuit/` | Produces small A4 bundles, which the app lane uses as early fixtures |
| **L3a core**: non-visual Swift, built outside Bitrig | `App/Core/` | Consumes A4. Provides the `CaseBundle` loader (JSON + raw → arrays and 3D texture descriptors) and the A1/A2 cut-plane and hinge math as pure Swift, with no SwiftUI or Metal views |
| **L3b UI**: **built in Bitrig, account A** | `Project.json`, `App/App.swift`, `App/ContentView.swift`, `App/UI/` | Case picker, demo banner, credits, layer, finding and cut controls, and the compact / iPad screens. Consumes `docs/contracts/render-interface.md` |
| **L3c render + Duo**: **built in Bitrig, account B** | `App/Render/`, `App/Duo/` | The Metal slice shader, `SliceView`, `OverviewView`, the hinge driver and the Duo pose layout. Starts by de-risking the iOS 27.1 SDK, the Duo simulator and the hinge API. Provides `docs/contracts/render-interface.md` |
| **Commander**: integration | `docs/`, `coordination/`, `AGENTS.md`, `CLAUDE.md`, `App/Cases/body/`, `App/Cases/head/` | Copies L1 output into the app and records sizes |

`docs/PRD.md` addendum A4 is the **only** interface between the data lanes and the app lane. If A4 is wrong, propose an addendum. Don't quietly change the format in one lane.

## Branches

- The integration branch is `demo/addenda-and-pipeline`. `main` is updated only when Daniel says so.
- A worker on its own machine or worktree uses `agent/<agent-id>/<lane>`. Workers inside the Commander's session share the demo branch checkout, which is safe because their paths don't overlap. There, the Commander does the committing.
- Merge by fast-forward or rebase only. Don't rewrite history on shared branches.

## Task states

`assigned → in_progress → ready_for_integration → integrated → verified` (or `blocked`). Workers set their own state in their handoff. The Commander mirrors it into TASKS.md.

## Handoff template (`coordination/handoffs/<lane>.md`)

```
# <lane> handoff
- Task / state / UTC time:
- Objective and acceptance criteria:
- Files changed:
- Checks run and result (command → pass/fail, key numbers):
- Evidence paths (previews, logs):
- Interface notes for other lanes:
- Fallbacks taken / scope cut:
- Blockers / requests:
- Next action (exact resumption step):
```

## Gates before integration

- **L1:** `data/verify.py` passes on both bundles, and a human-visible preview PNG exists for each, including the 60° oblique slice.
- **L2:** the same byte-layout checks as `verify.py`, and each bundle is under 2 MB.
- **L3a:**
  - `xcrun -sdk iphonesimulator swiftc -typecheck` passes on `App/Core/*.swift`.
  - A small self-test loads an L2 bundle and checks the A2 mapping points.
  - A fresh read-only reviewer has checked the loader against A4. The reviewer gets only the contract, the diff and the check output.
- **L3b / L3c:** each builds and runs in Bitrig's simulator (L3c on the Duo simulator), and each prompt's acceptance check in `docs/bitrig-prompts.md` passes by eye. After the Commander merges both branches, the combined app must build in Bitrig.
- **Demo gate:** Daniel runs the A7 must-list in Bitrig on the simulator.

## Timebox

| Time | Milestone |
|---|---|
| T+0:15 | Lanes started |
| T+1:00 | L2 fixtures in the app, and the viewer renders a slice |
| T+1:45 | L1 bundles land |
| T+2:15 | Integrated and reviewed |
| T+2:15 to 3:00 | Rehearsal and fixes only. No new features |

If a lane stalls for more than 10 minutes, take its documented fallback and say so in its handoff.
