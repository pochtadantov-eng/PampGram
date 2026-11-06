#!/usr/bin/env python3
"""Apply PampGram feature integration hooks after the base patches.

Runs AFTER telegram-ios.patch + seends-cryptobot.patch + apply-profile-visuals.py.
Anchor-checked: fails loudly if Telegram changes a matched string.
"""

from pathlib import Path
import sys


def replace_once(path: Path, label: str, old: str, new: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        print(
            f"FAIL [{label}]: expected 1 match, found {count} in {path}",
            file=sys.stderr,
        )
        sys.exit(1)
    path.write_text(text.replace(old, new, 1))
    print(f"  OK: {label}")


def insert_after(path: Path, label: str, anchor: str, insertion: str) -> None:
    text = path.read_text()
    count = text.count(anchor)
    if count < 1:
        print(f"FAIL [{label}]: anchor not found in {path}", file=sys.stderr)
        sys.exit(1)
    idx = text.index(anchor) + len(anchor)
    path.write_text(text[:idx] + insertion + text[idx:])
    print(f"  OK: {label}")


def add_dep_if_missing(build_path: Path, label: str, after_dep: str) -> None:
    text = build_path.read_text()
    pampgram_dep = '"//submodules/TelegramUI/Components/PampGram/PampGramCore"'
    if pampgram_dep in text:
        print(f"  SKIP: {label} (already present)")
        return
    anchor = after_dep + ","
    if anchor not in text:
        print(f"FAIL [{label}]: anchor dep (with comma) not found in {build_path}", file=sys.stderr)
        sys.exit(1)
    idx = text.index(anchor) + len(anchor)
    build_path.write_text(
        text[:idx] + "\n        " + pampgram_dep + "," + text[idx:]
    )
    print(f"  OK: {label}")


def add_import_if_missing(swift_path: Path, label: str, after_import: str) -> None:
    text = swift_path.read_text()
    if "import PampGramCore" in text:
        print(f"  SKIP: {label} (already present)")
        return
    if after_import not in text:
        print(f"FAIL [{label}]: anchor import not found in {swift_path}", file=sys.stderr)
        sys.exit(1)
    idx = text.index(after_import) + len(after_import)
    swift_path.write_text(text[:idx] + "import PampGramCore\n" + text[idx:])
    print(f"  OK: {label}")


print("PampGram: applying feature integration hooks...")

# ---------------------------------------------------------------------------
# 1. ChatTimeMachine — timestamp override
# ---------------------------------------------------------------------------
print("\n[1/6] ChatTimeMachine timestamp override")

ts_swift = Path(
    "submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode/"
    "Sources/StringForMessageTimestampStatus.swift"
)
ts_build = Path(
    "submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode/BUILD"
)

add_dep_if_missing(
    ts_build,
    "ChatMessageDateAndStatusNode BUILD dep",
    '"//submodules/TelegramPresentationData"',
)

add_import_if_missing(ts_swift, "timestamp import PampGramCore", "import AccountContext\n")

replace_once(
    ts_swift,
    "timestamp override hook",
    "        } else {\n"
    "            timestamp = message.timestamp\n"
    "        }\n"
    "    }",
    "        } else {\n"
    "            timestamp = message.timestamp\n"
    "        }\n"
    "    }\n"
    "\n"
    "    if let override = PampGramChatTimeMachineRuntime.shared.getOverrideTimestamp(messageId: message.id) {\n"
    "        timestamp = override\n"
    "    }",
)

# ---------------------------------------------------------------------------
# 2. VideoMessageSaver — auto-save on playback
# ---------------------------------------------------------------------------
print("\n[2/6] VideoMessageSaver auto-save")

video_swift = Path(
    "submodules/TelegramUI/Components/Chat/"
    "ChatMessageInteractiveInstantVideoNode/Sources/"
    "ChatMessageInteractiveInstantVideoNode.swift"
)

replace_once(
    video_swift,
    "auto-save video circle on playback",
    "                    if let updatedPlaybackStatus = updatedPlaybackStatus {",
    "                    if PampGramVideoMessageSaver.shared.isEnabled(accountKey: item.context.account.peerId.toInt64()) {\n"
    "                        PampGramVideoMessageSaver.shared.saveIfNeeded(postbox: item.context.account.postbox, message: item.message)\n"
    "                    }\n"
    "                    if let updatedPlaybackStatus = updatedPlaybackStatus {",
)

# ---------------------------------------------------------------------------
# 3. FakeBadge — Premium star in own profile
# ---------------------------------------------------------------------------
print("\n[3/6] FakeBadge premium star override")

header_swift = Path(
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/"
    "Sources/PeerInfoHeaderNode.swift"
)

replace_once(
    header_swift,
    "fake badge isPremium override",
    "            isPremium = peer.isPremium\n"
    "            isVerified = peer.isVerified",
    "            isPremium = peer.isPremium\n"
    "            if !isPremium && PampGramFakeBadgeRuntime.shared.isEnabled(accountKey: self.context.account.peerId.toInt64()) && peer.id == self.context.account.peerId {\n"
    "                isPremium = true\n"
    "            }\n"
    "            isVerified = peer.isVerified",
)

# ---------------------------------------------------------------------------
# 4. FakeSubscribers — member count override
# ---------------------------------------------------------------------------
print("\n[4/6] FakeSubscribers member count override")

profile_items_swift = Path(
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/"
    "Sources/PeerInfoProfileItems.swift"
)

replace_once(
    profile_items_swift,
    "fake subscribers count",
    "                            let memberCount = cachedData.participantsSummary.memberCount ?? 0",
    "                            var memberCount = cachedData.participantsSummary.memberCount ?? 0\n"
    "                            if PampGramFakeSubscribersRuntime.shared.isEnabled(accountKey: context.account.peerId.toInt64()),\n"
    "                               let override = PampGramFakeSubscribersRuntime.shared.overrideCount(accountKey: context.account.peerId.toInt64()) {\n"
    "                                memberCount = Int32(clamping: override)\n"
    "                            }",
)

# ---------------------------------------------------------------------------
# 5. FakeDeletedAccount — name override in profile header
# ---------------------------------------------------------------------------
print("\n[5/6] FakeDeletedAccount profile name override")

replace_once(
    header_swift,
    "fake deleted account name override",
    "                title = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)",
    "                title = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)\n"
    "                if PampGramFakeDeletedAccountRuntime.shared.isEnabled(accountKey: self.context.account.peerId.toInt64()) && peer.id == self.context.account.peerId {\n"
    "                    title = PampGramFakeDeletedAccountRuntime.deletedAccountName\n"
    "                }",
)

# ---------------------------------------------------------------------------
# 6. Wallet collectibles -> gift store (new in 13.x): the gift store controller takes the
#    mod's visual-gift flow, which a plain Wallet call leaves at the real behaviour.
# ---------------------------------------------------------------------------
print("\n[6/6] WalletCollectibleScreen gift store flow")

replace_once(
    Path(
        "submodules/TelegramUI/Components/Wallet/WalletCollectibleScreen/"
        "Sources/WalletCollectibleScreen.swift"
    ),
    "wallet gift store flow",
    "makeGiftStoreController(context: context, peerId: context.account.peerId, gift: gift)",
    "makeGiftStoreController(context: context, peerId: context.account.peerId, gift: gift, pampGramGiftFlow: .real)",
)

# ---------------------------------------------------------------------------
print("\nPampGram: feature hooks done.")
print("  ACTIVE: ChatTimeMachine, VideoMessageSaver, FakeBadge, FakeSubscribers, FakeDeletedAccount")
print("  CONTEXT MENU ONLY: FakeForward, FakeReactions, FakeActivity, InvisibleMessage, ReactionSpammer,")
print("    FakeSystemMessages, FakePaymentReceipt, FakeIncomingCall, FakeScreenshotNotification")
