#!/usr/bin/env python3
"""Register PampGram's files in Telegram-iOS's Postbox allowlists.

Telegram-iOS 13.x runs build-system/Make/PostboxImportCheck.py before every build and fails it if
a Swift file outside TelegramCore imports Postbox or uses `.postbox` without being listed in
submodules/Postbox/AllowedImporters.txt / AllowedPostboxAccess.txt. The mod is written directly
against Postbox, so this rewrites both lists to exactly what the patched tree contains.

Runs AFTER the patches, the component copy and the other post-patch scripts, from the root of
the Telegram-iOS checkout.
"""

import os
import sys

sys.path.insert(0, os.path.join("build-system", "Make"))
import PostboxImportCheck as check  # noqa: E402


def rewrite(list_path: str, found: dict) -> None:
    with open(list_path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    header = []
    for line in lines:
        if line.startswith("#") or not line.strip():
            header.append(line)
        else:
            break
    while header and not header[-1].strip():
        header.pop()
    with open(list_path, "w", encoding="utf-8") as f:
        f.write("\n".join(header + sorted(found)) + "\n")
    print("  OK: {} ({} entries)".format(list_path, len(found)))


base = os.getcwd()
importers, accessors, conformance_errors = check.scan_tree(base)

if conformance_errors:
    for error in conformance_errors:
        print("FAIL: " + error, file=sys.stderr)
    sys.exit(1)

print("PampGram: registering Postbox users...")
rewrite(check.ALLOWLIST_PATH, importers)
rewrite(check.ACCESS_ALLOWLIST_PATH, accessors)

errors = check.check(base)
if errors:
    for error in errors:
        print("FAIL: " + error, file=sys.stderr)
    sys.exit(1)
print("PampGram: PostboxImportCheck passes.")
