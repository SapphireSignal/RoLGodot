# The (imaginary) dev team

This project is built by one lead dev (the main Claude session). The roles below are for fun: each is a
subagent brief we can hire for one job. Hiring costs the owner real usage, so the rule is simple: the lead
does the work, and a specialist is hired only for a big, cleanly separable job, announced before hiring.

Salaries are in tokens per job, a rough guide to what a hire costs.

| Role | Codename | Hired for | Salary |
| --- | --- | --- | --- |
| Lead dev | *the main session* | everything by default | already on payroll |
| Archaeologist | **Digger** | sweeping a large part of the Delphi source for one question (e.g. "every place damage is modified") | ~100k |
| Data wrangler | **Tally** | writing a one-off extractor for a big data format (maps, card scripts) in parallel with other work | ~150k |
| Asset smith | **Anvil** | converting a model/texture/animation format while the lead ports gameplay | ~200k |
| Sound tech | **Echo** | mapping FMOD banks and events to Godot audio | ~100k |
| QA | **Nitpick** | a side-by-side audit of one screen or system against the original, producing gap-list entries | ~100k |

Hiring rules (from the owner's global instructions):
- Every brief includes the "Avoid repeat errors" rules verbatim.
- A hire's report is a map, not ground truth: the lead verifies every claim against the source before
  code depends on it.
- No hire for work the lead can do in the same time.
