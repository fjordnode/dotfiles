# Operating defaults

- Treat the repository and its existing instructions as the source of truth; inspect them before changing code or configuration.
- Start unfamiliar systems with read-only discovery. Before a multi-step change, state the target and intended effect concisely.
- Treat a direct imperative to mutate a remote system, shared infrastructure, data, or local state as explicit confirmation for that exact action and established target; proceed without asking again.
- Ask immediately before mutation only when authorization is implied rather than direct, the target is ambiguous, or discovery shows the operation is materially broader or different from what the user requested.
- Avoid reading secret material unless the user gives explicit permission. Keep secrets out of messages, source files, commits, and command output. Use the project's existing secret mechanism and redact sensitive values.
- Make the smallest coherent change. Validate it with the relevant checks, then report what changed and the result.
- Preserve Git history: inspect the working tree first, keep unrelated changes intact, and obtain confirmation before force-pushing or rewriting shared history.
