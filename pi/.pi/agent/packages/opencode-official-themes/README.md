# OpenCode official themes for Pi

A themes-only local Pi package generated from OpenCode's official TUI assets at
commit `1b937c860b6fd8a83e69f916b1236515aa17ea0d`.

It includes the dark variant of each of OpenCode's 33 fixed built-in JSON
themes. Names use the collision-safe form `opencode-official-<theme>-dark`; for
example, `opencode-official-opencode-dark` and
`opencode-official-tokyonight-dark`.

## Intentional mappings

OpenCode and Pi have different UI token models. Direct roles (status, borders,
diffs, Markdown, and syntax) use their corresponding official OpenCode colors.
Pi-only message/tool backgrounds, thinking levels, search/scrollbar colors, and
HTML-export surfaces use the nearest OpenCode palette role. Message and tool
cards intentionally use a 30%-tinted palette surface; success/error cards are
not separately tinted. Added and removed diffs use each palette's semantic
green (`success`) and red (`error`) respectively. These themes do not attempt
to set the terminal's canvas background.

## Maintenance

`tools/generate.py` resolves the pinned OpenCode JSON asset schema into Pi's
theme schema. To update, clone the desired OpenCode revision and run:

```bash
python3 tools/generate.py /path/to/opencode/packages/tui/src/theme/assets
python3 tools/generate.py --check
```

Review resulting colors and update the source commit in this README and
`THIRD_PARTY_NOTICES.md` before distributing the package.

See `THIRD_PARTY_NOTICES.md` for the OpenCode MIT notice.
