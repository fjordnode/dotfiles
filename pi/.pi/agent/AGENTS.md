# Operating defaults

- Treat the repository and its existing instructions as the source of truth; inspect them before changing code or configuration.
- Start unfamiliar systems with read-only discovery. Before a multi-step change, state the target and intended effect concisely.
- Treat a direct imperative to mutate a remote system, shared infrastructure, data, or local state as explicit confirmation for that exact action and established target; proceed without asking again.
- Ask immediately before mutation only when authorization is implied rather than direct, the target is ambiguous, or discovery shows the operation is materially broader or different from what the user requested.
- Avoid reading secret material unless the user gives explicit permission. Keep secrets out of messages, source files, commits, and command output. Use the project's existing secret mechanism and redact sensitive values.
- Make the smallest coherent change. Use risk-proportional validation: run only checks that address a plausible failure mode introduced by the change. For prose-only documentation edits, inspect the diff and any relevant formatting or link checks; skip test suites and builds unless the documentation is compiled, executable, generated, or otherwise affects them. Report what changed and the validation performed.
- Preserve Git history: inspect the working tree first, keep unrelated changes intact, and obtain confirmation before force-pushing or rewriting shared history.

# Memory

- Read `~/.pi/agent/memory.md` at the start of a session. Append to it only when the user says "remember this"; keep entries one line, under the matching heading. It holds preferences, corrections, and small personal facts. Repository documentation wins over it for anything about hosts, networks, or services.
- Recall earlier sessions with `pi-session-finder` rather than from memory.
