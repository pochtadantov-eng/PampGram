#!/usr/bin/env python3
"""Apply PampGram crash-recovery hooks to AppDelegate after the base Telegram patch.

If the app crashes on startup (e.g. a sticker-render crash on the last-opened chat
restores that same chat and crashes again in a loop), PampGramCrashRecovery detects
the loop on the next boot and clears Telegram's saved navigation state so the app
starts from the chat list.
"""

from pathlib import Path
import sys


def replace_once(path: Path, label: str, old: str, new: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        print(
            f"PampGram crash-recovery post-patch failed [{label}]: "
            f"expected 1 match, found {count}",
            file=sys.stderr,
        )
        sys.exit(1)
    path.write_text(text.replace(old, new, 1))
    print(f"OK: {label}")


appdelegate_path = Path(
    "submodules/TelegramUI/Sources/AppDelegate.swift"
)

replace_once(
    appdelegate_path,
    "import PampGramCore into AppDelegate",
    "import UIKit\n",
    "import UIKit\nimport PampGramCore\n",
)

replace_once(
    appdelegate_path,
    "call onWillLaunch at app startup",
    "    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {\n",
    "    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {\n        PampGramCrashRecovery.onWillLaunch()\n",
)

replace_once(
    appdelegate_path,
    "call onBecameActive once UI is up",
    "    func applicationDidBecomeActive(_ application: UIApplication) {\n",
    "    func applicationDidBecomeActive(_ application: UIApplication) {\n        PampGramCrashRecovery.onBecameActive()\n",
)

print("PampGram: crash recovery integration complete.")
