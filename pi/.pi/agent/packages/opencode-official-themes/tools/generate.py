#!/usr/bin/env python3
"""Generate Pi themes from OpenCode TUI JSON assets.

The input directory must contain the official OpenCode theme asset JSON files.
This generates only each theme's dark variant.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "themes"
REQUIRED = {
    "accent", "border", "borderAccent", "borderMuted", "success", "error", "warning",
    "muted", "dim", "text", "thinkingText", "selectedBg", "userMessageBg",
    "userMessageText", "customMessageBg", "customMessageText", "customMessageLabel",
    "toolPendingBg", "toolSuccessBg", "toolErrorBg", "toolTitle", "toolOutput",
    "mdHeading", "mdLink", "mdLinkUrl", "mdCode", "mdCodeBlock", "mdCodeBlockBorder",
    "mdQuote", "mdQuoteBorder", "mdHr", "mdListBullet", "toolDiffAdded",
    "toolDiffRemoved", "toolDiffContext", "syntaxComment", "syntaxKeyword",
    "syntaxFunction", "syntaxVariable", "syntaxString", "syntaxNumber", "syntaxType",
    "syntaxOperator", "syntaxPunctuation", "thinkingOff", "thinkingMinimal",
    "thinkingLow", "thinkingMedium", "thinkingHigh", "thinkingXhigh", "bashMode",
}
OPTIONAL = {"thinkingMax", "scrollbarThumb", "searchMatchBg", "searchMatchText"}


def resolve(value, defs, variant):
    """Resolve an OpenCode literal, definition reference, or dark/light variant."""
    if isinstance(value, dict):
        return resolve(value[variant], defs, variant)
    if isinstance(value, str) and value in defs:
        return resolve(defs[value], defs, variant)
    if not isinstance(value, str):
        raise ValueError(f"Unsupported color value: {value!r}")
    # OpenCode supports transparent `none`; Pi uses its terminal default instead.
    return "" if value == "none" else value


def normalize_for_pi(value, background):
    """Convert OpenCode-only transparency/shorthand to Pi's #RRGGBB format.

    Pi has no alpha channel. Eight-digit RGBA colors are composited onto the
    theme canvas, and transparent surfaces become the canvas color.
    """
    if value in {"none", "transparent"}:
        return background
    if len(value) == 4 and value.startswith("#"):
        return "#" + "".join(ch * 2 for ch in value[1:])
    if len(value) == 9 and value.startswith("#"):
        r, g, b, alpha = (int(value[i : i + 2], 16) for i in range(1, 9, 2))
        br, bg, bb = (int(background[i : i + 2], 16) for i in range(1, 7, 2))
        opacity = alpha / 255
        return "#{:02x}{:02x}{:02x}".format(
            round(r * opacity + br * (1 - opacity)),
            round(g * opacity + bg * (1 - opacity)),
            round(b * opacity + bb * (1 - opacity)),
        )
    return value


def blend(base, overlay, overlay_opacity):
    """Return an opaque, subtle surface between two #RRGGBB palette colors."""
    base_rgb = (int(base[i : i + 2], 16) for i in range(1, 7, 2))
    overlay_rgb = (int(overlay[i : i + 2], 16) for i in range(1, 7, 2))
    return "#{:02x}{:02x}{:02x}".format(*(
        round(b * (1 - overlay_opacity) + o * overlay_opacity)
        for b, o in zip(base_rgb, overlay_rgb)
    ))


def pi_theme(slug, source, variant):
    defs = source.get("defs", {})
    raw = source["theme"]
    background = resolve(raw["background"], defs, variant)
    background = normalize_for_pi(background, "#000000")
    c = {key: normalize_for_pi(resolve(value, defs, variant), background)
         for key, value in raw.items() if key != "thinkingOpacity"}
    # A 30% panel tint keeps Pi's cards distinguishable without OpenCode's
    # stronger nested-panel effect or colored success/error card backgrounds.
    soft_surface = blend(c["background"], c["backgroundPanel"], 0.30)
    # These exact roles are deliberately mapped where Pi has a semantic match.
    colors = {
        "accent": c["primary"], "border": c["border"],
        "borderAccent": c["borderActive"], "borderMuted": c["borderSubtle"],
        "success": c["success"], "error": c["error"], "warning": c["warning"],
        "muted": c["textMuted"], "dim": c["textMuted"], "text": c["text"],
        "thinkingText": c["textMuted"], "selectedBg": c["backgroundElement"],
        "scrollbarThumb": c["border"], "searchMatchBg": c["backgroundElement"],
        "searchMatchText": c["primary"],
        "userMessageBg": soft_surface, "userMessageText": c["text"],
        "customMessageBg": soft_surface, "customMessageText": c["text"],
        "customMessageLabel": c["secondary"], "toolPendingBg": soft_surface,
        "toolSuccessBg": soft_surface, "toolErrorBg": soft_surface,
        "toolTitle": c["primary"], "toolOutput": c["text"],
        "mdHeading": c["markdownHeading"], "mdLink": c["markdownLinkText"],
        "mdLinkUrl": c["markdownLink"], "mdCode": c["markdownCode"],
        "mdCodeBlock": c["markdownCodeBlock"], "mdCodeBlockBorder": c["borderSubtle"],
        "mdQuote": c["markdownBlockQuote"], "mdQuoteBorder": c["markdownBlockQuote"],
        "mdHr": c["markdownHorizontalRule"], "mdListBullet": c["markdownListItem"],
        "toolDiffAdded": c["success"], "toolDiffRemoved": c["error"],
        "toolDiffContext": c["diffContext"], "syntaxComment": c["syntaxComment"],
        "syntaxKeyword": c["syntaxKeyword"], "syntaxFunction": c["syntaxFunction"],
        "syntaxVariable": c["syntaxVariable"], "syntaxString": c["syntaxString"],
        "syntaxNumber": c["syntaxNumber"], "syntaxType": c["syntaxType"],
        "syntaxOperator": c["syntaxOperator"], "syntaxPunctuation": c["syntaxPunctuation"],
        # Pi-only editor-state colors are ordered from subtle to prominent.
        "thinkingOff": c["borderSubtle"], "thinkingMinimal": c["border"],
        "thinkingLow": c["primary"], "thinkingMedium": c["secondary"],
        "thinkingHigh": c["accent"], "thinkingXhigh": c["error"],
        "thinkingMax": c["warning"], "bashMode": c["warning"],
    }
    return {
        "$schema": "https://raw.githubusercontent.com/badlogic/pi-mono/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json",
        "name": f"opencode-official-{slug}-{variant}",
        "colors": colors,
        "export": {"pageBg": c["background"], "cardBg": c["backgroundPanel"], "infoBg": c["backgroundElement"]},
    }


def check():
    files = sorted(OUT.glob("*.json"))
    assert len(files) == 33, f"Expected 33 themes, found {len(files)}"
    names = set()
    for path in files:
        theme = json.loads(path.read_text())
        missing = REQUIRED - set(theme["colors"])
        assert not missing, f"{path.name}: missing {sorted(missing)}"
        assert REQUIRED | OPTIONAL >= set(theme["colors"]), f"{path.name}: unknown color token"
        assert theme["name"] not in names, f"Duplicate theme name: {theme['name']}"
        names.add(theme["name"])
    print(f"Validated {len(files)} Pi theme files with {len(names)} unique names.")


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--check":
        check()
        return
    if len(sys.argv) != 2:
        raise SystemExit("Usage: generate.py <opencode-theme-assets-dir> | --check")
    source_dir = Path(sys.argv[1])
    assets = sorted(source_dir.glob("*.json"))
    if len(assets) != 33:
        raise SystemExit(f"Expected 33 OpenCode JSON assets, found {len(assets)} in {source_dir}")
    OUT.mkdir(exist_ok=True)
    for old in OUT.glob("*.json"):
        old.unlink()
    for asset in assets:
        source = json.loads(asset.read_text())
        theme = pi_theme(asset.stem, source, "dark")
        target = OUT / f"{theme['name']}.json"
        target.write_text(json.dumps(theme, indent=2) + "\n")
    check()


if __name__ == "__main__":
    main()
