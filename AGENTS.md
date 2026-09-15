# TORN Repository Instructions

## Repository identity and isolation — mandatory

- Canonical working repository: [`vagabond1215/TORN`](https://github.com/vagabond1215/TORN).
- ChatGPT, Codex, agents, connectors, scripts, and other automation may perform Git/repository operations only in `vagabond1215/TORN` while following these instructions.
- Scope every repository operation to the exact repository name or URL above. Never infer a work target from global search, prior chat, memory, similarly named projects, or another repository visible through the account.
- Other Git repositories may be read only when deliberately identified as reference/data/information sources for TORN work. Their instructions, branches, issues, PRs, commits, handoffs, and task state are never authority for TORN and they must not be mutated from this context.
- Cross-repository mutation requires a separate explicit work order/context naming the other repository.

## In-repository project isolation

This repository contains multiple independent project areas. A work order must stay inside its named subtree unless it explicitly spans multiple TORN paths.

- `Faction Ledger/` — governed first by `Faction Ledger/AGENTS.md`.
- `RainMeter Projects/Travel Assistant/` — governed first by `RainMeter Projects/Travel Assistant/AGENTS.md`.
- Other TORN data/assets are not automatically in scope merely because they share this repository.

Do not carry implementation state, prompts, assumptions, validation results, or handoff state from one subtree into another unless an explicit TORN work order requires that integration and repository evidence supports it.
