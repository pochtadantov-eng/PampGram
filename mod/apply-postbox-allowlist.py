#!/usr/bin/env python3
"""Register PampGram's files in Telegram-iOS's Postbox allowlists.

Telegram-iOS 13.x runs build-system/Make/PostboxImportCheck.py before every build and fails it if
a Swift file outside TelegramCore imports Postbox or uses `.postbox` without being listed in
submodules/Postbox/AllowedImporters.txt / AllowedPostboxAccess.txt. The mod is written directly
against Postbox, so this rewrites both lists to exactly what the patched tree contains.

It also extends the Bazel `package_group` in submodules/Postbox/BUILD that decides which
packages may depend on the Postbox target at all, with every package whose BUILD file does.

Runs AFTER the patches, the component copy and the other post-patch scripts, from the root of
the Telegram-iOS checkout.
"""

import os
import re
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


def register_bazel_clients(base: str) -> None:
    build_path = os.path.join(base, "submodules", "Postbox", "BUILD")
    with open(build_path, encoding="utf-8") as f:
        text = f.read()

    listed = set(re.findall(r'"(//[^"]*)"', text.split("swift_library(", 1)[0]))
    needed = []
    for directory, subdirectories, filenames in os.walk(base):
        subdirectories[:] = [
            name for name in subdirectories
            if name not in (".git", "node_modules") and not name.startswith("bazel-")
        ]
        if "BUILD" not in filenames:
            continue
        relative = os.path.relpath(directory, base).replace(os.sep, "/")
        if relative == "submodules/Postbox":
            continue
        label = "//" + relative
        if label in listed:
            continue
        with open(os.path.join(directory, "BUILD"), encoding="utf-8", errors="replace") as f:
            content = f.read()
        if re.search(r'"//submodules/Postbox(?::Postbox)?"', content):
            needed.append(label)

    if not needed:
        print("  OK: Postbox package_group already covers every client")
        return

    marker = '        "//submodules/TemporaryCachedPeerDataManager",\n    ],\n)'
    if text.count(marker) != 1:
        print("FAIL: cannot find the end of the Postbox clients package_group", file=sys.stderr)
        sys.exit(1)
    extra = "".join('        "{}",\n'.format(label) for label in sorted(needed))
    text = text.replace(marker, '        "//submodules/TemporaryCachedPeerDataManager",\n' + extra + "    ],\n)")
    with open(build_path, "w", encoding="utf-8") as f:
        f.write(text)
    print("  OK: Postbox package_group += {}".format(", ".join(sorted(needed))))


base = os.getcwd()
importers, accessors, conformance_errors = check.scan_tree(base)

if conformance_errors:
    for error in conformance_errors:
        print("FAIL: " + error, file=sys.stderr)
    sys.exit(1)

print("PampGram: registering Postbox users...")
rewrite(check.ALLOWLIST_PATH, importers)
rewrite(check.ACCESS_ALLOWLIST_PATH, accessors)
register_bazel_clients(base)

errors = check.check(base)
if errors:
    for error in errors:
        print("FAIL: " + error, file=sys.stderr)
    sys.exit(1)
print("PampGram: PostboxImportCheck passes.")
