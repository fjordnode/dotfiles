# File Deletion Policy

NEVER use `rm`, `/bin/rm`, `unlink`, or any delete command.

Instead, archive files preserving their full path structure:
```bash
# Example: archiving /home/hugo/.appdata/compose/old-file.json
mkdir -p /home/hugo/claude-archive/home/hugo/.appdata/compose/
mv /home/hugo/.appdata/compose/old-file.json /home/hugo/claude-archive/home/hugo/.appdata/compose/
```

This preserves the original location for easy restoration:
```bash
mv /home/hugo/claude-archive/home/hugo/.appdata/compose/old-file.json /home/hugo/.appdata/compose/
```

This applies to ALL directories, not just the current working directory.
