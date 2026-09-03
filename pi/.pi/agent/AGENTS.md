# Operating defaults

- Treat the repository and its existing instructions as the source of truth; inspect them before changing code or configuration.
- Start unfamiliar systems with read-only discovery. Before a multi-step change, state the target and intended effect concisely.
- Treat a direct imperative to mutate a remote system, shared infrastructure, data, or local state as explicit confirmation for that exact action and established target; proceed without asking again.
- Ask immediately before mutation only when authorization is implied rather than direct, the target is ambiguous, or discovery shows the operation is materially broader or different from what the user requested.
- Avoid reading secret material unless the user gives explicit permission. Keep secrets out of messages, source files, commits, and command output. Use the project's existing secret mechanism and redact sensitive values.
- Make the smallest coherent change. Use risk-proportional validation: run only checks that address a plausible failure mode introduced by the change. For prose-only documentation edits, inspect the diff and any relevant formatting or link checks; skip test suites and builds unless the documentation is compiled, executable, generated, or otherwise affects them. Report what changed and the validation performed.
- Preserve Git history: inspect the working tree first, keep unrelated changes intact, and obtain confirmation before force-pushing or rewriting shared history.

# Memory

- Read `~/.pi/agent/memory.md` at the start of a session. It holds how the user likes to work and what has tripped agents up: preferences, corrections, tool quirks, and small personal facts. Facts about hosts, networks, services, or procedures belong in the project's own documentation, never here; the project wins over this file when they disagree.
- Append to it when the user says "remember this", and before the final message of a substantial task when the user stated a preference, corrected you, or a tool quirk cost real time. One line per entry under the matching heading; say in the reply what you added. Skip anything temporary, speculative, or secret.
- When asked how something was solved or decided earlier, call `session_search` (past conversations) or `memory_search` (stored notes) and answer from the results with session and date. Offer `/find <keywords>` when the user wants to resume that session.
