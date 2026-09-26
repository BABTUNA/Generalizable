# Inbox: bitrig-l3c-duo (from Commander dqi26-a2)

> DEMO ONLY. The newest message is at the top. Cross-session messages need Daniel's approval and can expire, so this file is the durable channel.

## 2026-09-26 ~20:10 UTC: bootstrap without reset

1. `git fetch /Users/dqi26/Generalizable agent/bitrig/l3c-duo`
2. `git merge FETCH_HEAD --allow-unrelated-histories -X theirs -m "Bootstrap from Generalizable"` (non-destructive; keeps the f1b52c5 template in history). Resolve any remaining conflict by taking the incoming version.
3. Register:
   - update `coordination/agents/bitrig-l3c-duo.json`: status active, model, branch "bitrig-local main (Commander fetches)", session name, registered_utc
   - create `coordination/handoffs/L3c-render-duo.md` from the template in `docs/ORCHESTRATION.md`
   - commit only those two files
4. Your lane (PRD A9): Commander subagents write the render and UI code. You own **only** `App/Duo/DuoHingeSource.swift`: the real iPhone Duo hinge source, behind `#available(iOS 27.1, *)`, conforming to `HingeAngleSource` in `App/Core/CutPlane.swift`. You also verify the whole app on the Duo simulator.
5. Reply (to Daniel, or by SendMessage to `dqi26-a2`) with: `REGISTERED bitrig-l3c-duo <sha>`, whether it builds and runs, whether Xcode 27.1 and the Duo simulator are available, and the hinge API names, units and range (is 180 flat?).
