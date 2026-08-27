---
name: herdr-handoff
description: Create a handoff and launch a fresh Pi agent in a new Herdr pane to continue it.
argument-hint: "What should the new agent focus on? Optional: focus the new pane."
disable-model-invocation: true
---

# Herdr handoff

Create a portable handoff, start a fresh Pi session in a sibling Herdr pane, and give that session the handoff.

Read and follow both source skills completely:

- [handoff](../handoff/SKILL.md) for the handoff document
- [Herdr](../herdr/SKILL.md) for runtime discovery and pane control

The source skills remain authoritative. This skill only coordinates them.

## Workflow

1. **Preflight Herdr.** Confirm `HERDR_ENV=1` and discover the installed Herdr CLI as required by the Herdr skill. Capture the current workspace, pane, cwd, and pane layout. Completion: the current Herdr pane and a valid split direction are known.

2. **Write the handoff.** Follow the handoff skill, treating the user's arguments as the new session's focus. Save the document in the OS temporary directory and retain its absolute path. Include enough current state, validation results, decisions, unresolved work, and suggested skills for a fresh agent; reference existing artifacts rather than copying them. Completion: the file exists, contains no secrets, and can be understood without this conversation.

3. **Create the sibling pane.** Split the current pane in the current workspace and cwd. Honor an explicitly requested direction; otherwise use the Herdr skill's layout rule. Keep focus on the current pane unless the user explicitly requested focus. Parse the new pane ID from Herdr's JSON response and give it a concise `handoff` label. Completion: the returned pane exists in the current workspace.

4. **Start fresh Pi.** Run only `pi` in the new pane, inspect its state, and wait until its agent status is `idle`. Do not resume or reuse the current Pi session. Completion: a fresh interactive Pi agent is ready in the new pane.

5. **Submit the continuation.** Send one prompt with `herdr pane run`:

   ```text
   Read the handoff document at <absolute-path>. Continue the work described there, prioritizing its stated focus. Invoke the suggested skills when applicable.
   ```

   Wait until the new agent reports `working` to confirm receipt. If the user requested focus, focus the new pane only after the prompt has been accepted. Completion: the new agent is working from the handoff.

6. **Relinquish.** Report the handoff path and new pane ID. Do not continue the handed-off task in the old session.

If pane creation or Pi startup fails, preserve and report the handoff path, inspect the pane as directed by the Herdr skill, and report the exact failure without creating a different workspace, tab, or worktree.
