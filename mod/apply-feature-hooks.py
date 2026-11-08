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
# 7. Triple tap on the bottom "Chats" tab opens PampGram's gifts section. The tab bar already
#    counts quick successive taps (debugTapCounter, used for the 10-tap debug menu); this adds
#    a callback at the third one and TelegramRootController answers it for the chats tab only.
# ---------------------------------------------------------------------------
print("\n[7/7] Triple tap on the Chats tab -> PampGram gifts")

tab_bar_swift = Path("submodules/TabBarUI/Sources/TabBarController.swift")
replace_once(
    tab_bar_swift,
    "tab bar triple-tap property",
    "    private var debugTapCounter: (Double, Int) = (0.0, 0)\n",
    "    private var debugTapCounter: (Double, Int) = (0.0, 0)\n"
    "    public var pampGramTripleTap: ((Int) -> Void)?\n",
)
replace_once(
    tab_bar_swift,
    "tab bar triple-tap hook",
    "                if strongSelf.debugTapCounter.1 >= 10 {",
    "                if strongSelf.debugTapCounter.1 == 3 {\n"
    "                    strongSelf.pampGramTripleTap?(index)\n"
    "                }\n"
    "                \n"
    "                if strongSelf.debugTapCounter.1 >= 10 {",
)

root_swift = Path("submodules/TelegramUI/Sources/TelegramRootController.swift")
replace_once(
    root_swift,
    "root controller import",
    "import TabBarUI\n",
    "import TabBarUI\nimport PampGramSettingsUI\n",
)
replace_once(
    root_swift,
    "root controller triple-tap handler",
    "        self.rootTabController = tabBarController\n        self.pushViewController(tabBarController, animated: false)\n",
    "        self.rootTabController = tabBarController\n"
    "        tabBarController.pampGramTripleTap = { [weak self, weak tabBarController, weak chatListController] index in\n"
    "            guard let self, let tabBarController, let chatListController else {\n"
    "                return\n"
    "            }\n"
    "            guard index >= 0 && index < tabBarController.controllers.count && tabBarController.controllers[index] === chatListController else {\n"
    "                return\n"
    "            }\n"
    "            pampGramOpenGiftsFromTabBar(context: self.context, navigationController: self)\n"
    "        }\n"
    "        self.pushViewController(tabBarController, animated: false)\n",
)

# ---------------------------------------------------------------------------
# 8. Real wallet + profile: fake GRAM balance on Telegram's own wallet card and "Balance" chip,
#    and a copied verification icon next to your own name in the real profile header.
# ---------------------------------------------------------------------------
print("\n[8] Wallet balance override + profile verification icon")

wallet_swift = Path("submodules/WalletContext/Sources/WalletContext.swift")
replace_once(
    wallet_swift,
    "wallet override hook",
    "public final class WalletContext {\n",
    "public final class WalletContext {\n"
    "    /// PampGram: when set and returning a value, the wallet reports that balance (nanograms)\n"
    "    /// instead of the real one. Set once at startup by TelegramRootController.\n"
    "    nonisolated(unsafe) public static var pampGramBalanceOverride: (() -> Int64?)?\n"
    "    /// PampGram: address to show as a visual wallet when the real one was never created.\n"
    "    nonisolated(unsafe) public static var pampGramAddressOverride: (() -> String?)?\n"
    "\n"
    "    static func pampGramApply(_ state: State) -> State {\n"
    "        guard let override = WalletContext.pampGramBalanceOverride, let balance = override() else {\n"
    "            return state\n"
    "        }\n"
    "        var phase = state.phase\n"
    "        if case .empty = state.phase, let address = WalletContext.pampGramAddressOverride?() {\n"
    "            phase = .wallet(WalletInfo(address: address, publicKey: \"\"))\n"
    "        }\n"
    "        guard case .wallet = phase else {\n"
    "            return state\n"
    "        }\n"
    "        return State(\n"
    "            phase: phase,\n"
    "            walletAddress: state.walletAddress,\n"
    "            balance: .value(balance, updatedAt: Int32(Date().timeIntervalSince1970)),\n"
    "            transactions: state.transactions,\n"
    "            collectibles: state.collectibles,\n"
    "            pendingTransfers: state.pendingTransfers,\n"
    "            activeOperation: state.activeOperation,\n"
    "            fiat: state.fiat,\n"
    "            gaslessInfo: state.gaslessInfo,\n"
    "            cardStickers: state.cardStickers,\n"
    "            cardStickerChangesPending: state.cardStickerChangesPending,\n"
    "            isSavingCardStickers: state.isSavingCardStickers,\n"
    "            cardStickerSaveError: state.cardStickerSaveError\n"
    "        )\n"
    "    }\n"
    "\n",
)
replace_once(
    wallet_swift,
    "wallet state signal override",
    "            |> deliverOnMainQueue).start(next: subscriber.putNext)",
    "            |> map { WalletContext.pampGramApply($0) }\n"
    "            |> deliverOnMainQueue).start(next: subscriber.putNext)",
)
replace_once(
    wallet_swift,
    "wallet state value override",
    "        self.output.currentState()\n",
    "        WalletContext.pampGramApply(self.output.currentState())\n",
)

replace_once(
    root_swift,
    "root controller wallet imports",
    "import TabBarUI\nimport PampGramSettingsUI\n",
    "import TabBarUI\nimport PampGramSettingsUI\nimport PampGramCore\nimport WalletContext\n",
)
replace_once(
    root_swift,
    "root controller wallet override install",
    "        tabBarController.pampGramTripleTap = {",
    "        PampGramVisualExtrasRuntime.shared.start(accountKey: self.context.account.peerId.toInt64(), postbox: self.context.account.postbox)\n"
    "        WalletContext.pampGramBalanceOverride = {\n"
    "            return PampGramVisualExtrasRuntime.shared.fakeBalanceNanos()\n"
    "        }\n"
    "        WalletContext.pampGramAddressOverride = {\n"
    "            return PampGramVisualExtrasRuntime.shared.fakeWalletAddress()\n"
    "        }\n"
    "        tabBarController.pampGramTripleTap = {",
)

replace_once(
    header_swift,
    "profile verification icon",
    "            if let verificationIconFileId = peer.verificationIconFileId {\n"
    "                verifiedIcon = .emojiStatus(PeerEmojiStatus(content: .emoji(fileId: verificationIconFileId), expirationDate: nil))\n"
    "            }\n",
    "            if let verificationIconFileId = peer.verificationIconFileId {\n"
    "                verifiedIcon = .emojiStatus(PeerEmojiStatus(content: .emoji(fileId: verificationIconFileId), expirationDate: nil))\n"
    "            }\n"
    "            if peer.id == self.context.account.peerId {\n"
    "                PampGramVisualExtrasRuntime.shared.start(accountKey: self.context.account.peerId.toInt64(), postbox: self.context.account.postbox)\n"
    "                if let pampGramFileId = PampGramVisualExtrasRuntime.shared.verificationFileId() {\n"
    "                    verifiedIcon = .emojiStatus(PeerEmojiStatus(content: .emoji(fileId: pampGramFileId), expirationDate: nil))\n"
    "                }\n"
    "            }\n",
)

# ---------------------------------------------------------------------------
# 9. Visual gift transfer through Telegram's own "Transfer" screen: the confirm alert shows the
#    local 25-Star fee ("Transfer for ⭐25"), Telegram doesn't check the real Stars balance for a
#    visual gift (the local fee is checked by sendGiftToPeer), and the transfer itself is local.
# ---------------------------------------------------------------------------
print("\n[9] Visual gift transfer: 25-Star fee in the original Transfer flow")

replace_once(
    Path("submodules/TelegramUI/Components/PeerInfo/PeerInfoVisualMediaPaneNode/Sources/PeerInfoGiftsPaneNode.swift"),
    "profile grid transfer fee",
    "                            let transferStars = gift.reference == nil ? 0 : (gift.transferStars ?? 0)\n",
    "                            let transferStars = gift.reference == nil ? PampGramPhantomGiftManager.transferFeeStars : (gift.transferStars ?? 0)\n"
    "                            if gift.reference == nil {\n"
    "                                PampGramPhantomGiftManager.markPhantomTransfer(slug: uniqueGift.slug)\n"
    "                            }\n",
)
gift_view_swift = Path("submodules/TelegramUI/Components/Gifts/GiftViewScreen/Sources/GiftViewScreen.swift")
replace_once(
    gift_view_swift,
    "gift screen transfer fee",
    "            let transferStars = arguments.transferStars ?? 0\n",
    # A visual gift reaches this screen either from the profile grid (no reference at all) or
    # from its local chat message (a reference to a message in the Local namespace, which the
    # server never saw). Both are handled locally.
    "            let pampGramIsPhantomGift: Bool\n"
    "            if let pampGramReference = arguments.reference, case let .message(pampGramMessageId) = pampGramReference {\n"
    "                pampGramIsPhantomGift = pampGramMessageId.namespace == Namespaces.Message.Local\n"
    "            } else {\n"
    "                pampGramIsPhantomGift = arguments.reference == nil\n"
    "            }\n"
    "            let transferStars = pampGramIsPhantomGift ? PampGramPhantomGiftManager.transferFeeStars : (arguments.transferStars ?? 0)\n"
    "            if pampGramIsPhantomGift {\n"
    "                PampGramPhantomGiftManager.markPhantomTransfer(slug: gift.slug)\n"
    "            }\n",
)
replace_once(
    gift_view_swift,
    "gift screen transfers a visual gift locally",
    "                    if let tranfserGiftImpl {\n"
    "                        return tranfserGiftImpl(transferStars == 0, reference, peerId)\n",
    "                    if pampGramIsPhantomGift {\n"
    "                        return PampGramPhantomGiftManager.sendUniqueGiftToPeer(context: context, uniqueGift: gift, peerId: peerId)\n"
    "                        |> castError(TransferStarGiftError.self)\n"
    "                        |> mapToSignal { success -> Signal<Never, TransferStarGiftError> in\n"
    "                            return success ? .complete() : .fail(.generic)\n"
    "                        }\n"
    "                    }\n"
    "                    if let tranfserGiftImpl {\n"
    "                        return tranfserGiftImpl(transferStars == 0, reference, peerId)\n",
)
replace_once(
    Path("submodules/TelegramUI/Sources/SharedAccountContext.swift"),
    "transfer alert skips the real balance check for visual gifts",
    "                    if transferStars > 0, let starsContext = context.starsContext, let starsState = starsContext.currentState {",
    "                    if transferStars > 0, !PampGramPhantomTransferMarker.shared.contains(slug: gift.slug), let starsContext = context.starsContext, let starsState = starsContext.currentState {",
)

# ---------------------------------------------------------------------------
# 10. Visual usernames in the real profile: listed as additional usernames next to the main
#     one; tapping one opens Telegram's own collectible-username sheet with the local price/date.
# ---------------------------------------------------------------------------
print("\n[10] Visual usernames in the profile")

profile_items_swift = Path(
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoProfileItems.swift"
)
replace_once(
    profile_items_swift,
    "additional usernames include the visual ones",
    "            let usernames = user.usernames.filter { $0.isActive && $0.username != mainUsername }\n"
    "            if !usernames.isEmpty {\n"
    "                additionalUsernames = presentationData.strings.Profile_AdditionalUsernames(String(usernames.map { \"@\\($0.username)\" }.joined(separator: \", \"))).string\n"
    "            }\n",
    "            var pampGramUsernameList = user.usernames.filter { $0.isActive && $0.username != mainUsername }.map { $0.username }\n"
    "            if user.id == context.account.peerId {\n"
    "                pampGramUsernameList.append(contentsOf: pampGramProfileVisuals.visualExtras.usernames.map { $0.name })\n"
    "            }\n"
    "            if !pampGramUsernameList.isEmpty {\n"
    "                additionalUsernames = presentationData.strings.Profile_AdditionalUsernames(String(pampGramUsernameList.map { \"@\\($0)\" }.joined(separator: \", \"))).string\n"
    "            }\n",
)
replace_once(
    profile_items_swift,
    "tapping a visual username opens the collectible sheet",
    "                                interaction.openUsername(String(username[username.index(username.startIndex, offsetBy: 1)...]), false, progress)\n",
    "                                let pampGramTapped = String(username[username.index(username.startIndex, offsetBy: 1)...])\n"
    "                                if user.id == context.account.peerId, let visual = pampGramProfileVisuals.visualExtras.usernames.first(where: { $0.name.lowercased() == pampGramTapped.lowercased() }) {\n"
    "                                    let info = TelegramCollectibleItemInfo(\n"
    "                                        subject: .username(visual.name),\n"
    "                                        purchaseDate: visual.boughtAt,\n"
    "                                        currency: \"USD\",\n"
    "                                        currencyAmount: visual.priceUsdCents,\n"
    "                                        cryptoCurrency: \"TON\",\n"
    "                                        cryptoCurrencyAmount: Int64((visual.priceTon * 1_000_000_000.0).rounded()),\n"
    "                                        url: \"https://fragment.com/username/\\(visual.name)\"\n"
    "                                    )\n"
    "                                    let initialData = CollectibleItemInfoScreen.pampGramLocalInitialData(peer: EnginePeer(user), subject: .username(visual.name), info: info)\n"
    "                                    interaction.getController()?.push(CollectibleItemInfoScreen(context: context, initialData: initialData))\n"
    "                                } else {\n"
    "                                    interaction.openUsername(pampGramTapped, false, progress)\n"
    "                                }\n",
)

# ---------------------------------------------------------------------------
print("\nPampGram: feature hooks done.")
print("  ACTIVE: ChatTimeMachine, VideoMessageSaver, FakeBadge, FakeSubscribers, FakeDeletedAccount")
print("  CONTEXT MENU ONLY: FakeForward, FakeReactions, FakeActivity, InvisibleMessage, ReactionSpammer,")
print("    FakeSystemMessages, FakePaymentReceipt, FakeIncomingCall, FakeScreenshotNotification")
