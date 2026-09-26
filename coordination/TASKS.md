# Task board (Commander-owned)

> **DEMO ONLY: 3-hour budget. Uses public open-source data. Not a diagnosis.** The process is in `docs/ORCHESTRATION.md`, and the scope order is in PRD addendum A7.

**Registered agents** (`coordination/agents/`): `commander-daniel-cc`, `cc-l1-data`, `cc-l2-synth`, `cc-l3a-core`, `cc-l3a-reviewer`, `cc-l4-viz`, `cc-sonnet-1` (**stopped**: its session ended, and the free-standing worker approach is retired), `bitrig-l3b` and `bitrig-l3c-duo` (**both not yet registered**: Daniel sends each one's Prompt 0). An unregistered agent's work is not integrated.

| ID | Lane | Owner | Branch | State | Notes |
|---|---|---|---|---|---|
| GZ-001 | L1 data | Claude subagent (Commander session) | demo/addenda-and-pipeline | integrated | Visible Human body + CQ500 head bundles, per the data-pipeline brief and A4 |
| GZ-002 | L2 synth | Claude subagent (Commander session) | demo/addenda-and-pipeline | integrated | Sun and Circuit board small A4 bundles; early fixtures for L3 |
| GZ-003 | L3a core | Claude subagent (Commander session) | demo/addenda-and-pipeline | integrated; review fix applied (7ee77ea) | `App/Core/`: CaseBundle loader + A1/A2 cut and hinge math. No views |
| GZ-005 | L3b UI | **Daniel + Bitrig account A** | agent/bitrig/l3b → merged by Commander | assigned | Screens and controls; consumes `docs/contracts/render-interface.md`. Driven by `docs/bitrig-prompts.md` track A |
| GZ-004 | Commander | Commander | demo/addenda-and-pipeline | in_progress | Integrate L1 into `App/Cases/`, review, hand to Daniel for the Bitrig demo run |
| GZ-006 | L3c render + Duo | **Daniel + Bitrig account B** | agent/bitrig/l3c-duo → merged by Commander | assigned | Metal `SliceView`, hinge driver, Duo layout. Its first report confirms or corrects the hinge API and the A2 mapping. `docs/bitrig-prompts.md` track B |
| GZ-007 | L4 viz reference | cc-l4-viz (Sonnet subagent) | demo/addenda-and-pipeline | integrated | Label cleanup + reference renderer + `docs/viz/SPEC.md` for the render lane |
| GZ-008 | L3c render | cc-l3c-render (Sonnet subagent) | agent/cc/l3c-render (worktree) | in_progress | Metal SliceView + 3D peel OverviewView per `docs/viz/SPEC.md` |
| GZ-009 | L3b UI | cc-l3b-ui (Sonnet subagent) | agent/cc/l3b-ui (worktree) | in_progress | Case picker, viewer controls, banner, credits |
