# Agents working in this repo

**This is a 3-hour hackathon DEMO, not a product.** It uses public open-source research data and makes no diagnosis.

## STEP 0 — REGISTER BEFORE YOU DO ANYTHING

**No agent edits a file until it has registered.** This applies to Claude Code, Codex, Bitrig's agent, and a teammate's agent alike. To register, create or update `coordination/agents/<agent-id>.json`:

```json
{
  "agent_id": "bitrig-l3b",
  "role": "commander | worker | reviewer",
  "kind": "claude-code-session | claude-subagent | codex | bitrig-agent | human",
  "model": "…",
  "machine": "…",
  "lane": "L1-data | L2-synth | L3a-core | L3b-visualization | …",
  "owns_paths": ["…"],
  "branch": "…",
  "handoff": "coordination/handoffs/<lane>.md",
  "session": "<Claude Code session name from ListAgents, or null for Bitrig>",
  "registered_utc": "…",
  "status": "active | done | blocked | stopped"
}
```

1. **Check the registrations first.** If another *active* agent already owns your lane or any of your paths, stop and tell the Commander. Don't start alongside it.
2. **Commit your registration as your first commit** on your branch, so every other agent can see it.
3. **Keep `status` current.** Set it to `done` or `stopped` when you finish or leave. A registration still marked `active` with no commit in the last 30 minutes counts as stale, and the Commander may reassign its lane.

The Commander also lists every agent in the table in `coordination/TASKS.md`. If a registration and the task board disagree, the registration file is what shows who is actually working.

## Talking to the Commander

- **Claude workers (Sonnet) are subagents that the Commander session (`dqi26-a2`) spawns.** The Commander registers them, gives them their lane in the spawn prompt, and receives their final report directly. There are no free-standing worker sessions. `docs/worker-registration-prompt.md` is retired.
- **Bitrig agents are prompted by Daniel inside Bitrig.** The Commander writes those prompts (`docs/bitrig-prompts.md`, or given in chat), and Daniel pastes them in and relays the replies. A Bitrig agent reports through its handoff file and its reply to Daniel.

## Then

- Read `docs/ORCHESTRATION.md`, then `docs/PRD.md` (including its **Addenda**), then `coordination/TASKS.md`.
- **Visualization (SwiftUI views, Metal, layouts, hinge) is built in Bitrig.** Outside Bitrig, work only on data, `App/Core/` non-visual Swift, and docs.
- Only edit the paths your lane owns.
- Record what you did in `coordination/handoffs/<lane>.md`.
- Propose spec changes as new PRD addenda. Don't edit the earlier PRD sections.
