#!/usr/bin/env python3
"""Block sponsored messages when PampGram's blockAds setting is on.

Runs as a post-patch step after the base Telegram-iOS patch.  It inserts
a guard into Telegram's ad-message request function so an empty result is
returned when PampGramAdBlockManager.shared.enabled is true — no network
request, no sponsored-message UI rendering.

The script probes known upstream file layouts for AdMessages and patches
whichever it finds.  A missing file is non-fatal (the toggle just has no
effect until the pattern is updated).
"""

from pathlib import Path
import re
import sys


def replace_once(path: Path, label: str, old: str, new: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        print(
            f"PampGram ad-blocking post-patch failed [{label}]: "
            f"expected 1 match, found {count}",
            file=sys.stderr,
        )
        sys.exit(1)
    path.write_text(text.replace(old, new, 1))
    print(f"OK: {label}")


# ── Locate AdMessages-related files ──────────────────────────────────
candidates = list(Path("submodules").rglob("AdMessages.swift"))
candidates += list(Path("submodules").rglob("AdMessage.swift"))
candidates += list(Path("submodules").rglob("ChatControllerAdMessages.swift"))

if not candidates:
    print(
        "PampGram ad-blocking post-patch: no AdMessages files found — "
        "skipping (toggle will be a no-op until upstream structure is mapped)",
        file=sys.stderr,
    )
    sys.exit(0)

patched = False

for path in candidates:
    text = path.read_text()

    if "import PampGramCore" not in text:
        import_matches = list(re.finditer(r"^import \w+.*$", text, re.MULTILINE))
        if import_matches:
            pos = import_matches[-1].end()
            text = text[:pos] + "\nimport PampGramCore" + text[pos:]

    # Pattern: func …adMessage…(…) -> Signal<…> {
    func_pattern = re.compile(
        r"(func\s+\w*[Aa]d[Mm]essage\w*\s*\([^)]*\)\s*->\s*Signal<[^{]*\{)",
        re.DOTALL,
    )
    for m in func_pattern.finditer(text):
        insertion_point = m.end()
        if "PampGramAdBlockManager" in text[insertion_point:insertion_point + 300]:
            continue
        guard_block = (
            "\n        if PampGramAdBlockManager.shared.enabled {\n"
            "            return .single([])\n"
            "        }\n"
        )
        text = text[:insertion_point] + guard_block + text[insertion_point:]
        patched = True
        print(f"OK: ad-message function guarded in {path}")
        break

    path.write_text(text)

if not patched:
    print(
        "PampGram ad-blocking post-patch: found candidate files but no "
        "matching function pattern — skipping",
        file=sys.stderr,
    )
    sys.exit(0)
