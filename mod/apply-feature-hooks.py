#!/usr/bin/env python3
"""Apply PampGram feature integration hooks after the base patches.

Runs AFTER telegram-ios.patch + seends-cryptobot.patch + apply-profile-visuals.py.
Anchor-checked: fails loudly if Telegram changes a matched string.
"""

from pathlib import Path
import sys


def replace_once(path: Path, label: str, old: str, new: str) -> None:
    text = path.read_text()
    # Prefer the "already applied" check first: after telegram-ios.patch on
    # release-13.2+, `old` may be gone while a distinctive part of `new` remains,
    # or `old` may still match as a substring and would otherwise duplicate.
    if new in text:
        print(f"  SKIP: {label} (already applied)")
        return
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
    if insertion and insertion in text:
        print(f"  SKIP: {label} (already applied)")
        return
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
    "    nonisolated(unsafe) public static var pampGramBalanceOverride: ((Int64) -> Int64?)?\n"
    "    /// PampGram: address to show as a visual wallet when the real one was never created.\n"
    "    nonisolated(unsafe) public static var pampGramAddressOverride: ((Int64) -> String?)?\n"
    "    /// PampGram: local Money history rows merged into the real wallet screen.\n"
    "    nonisolated(unsafe) public static var pampGramTransactionsOverride: ((Int64) -> [Transaction]?)?\n"
    "    /// PampGram: unique gifts from the owner's profile (real + visual) shown in Collectibles for sticking.\n"
    "    nonisolated(unsafe) public static var pampGramProfileCollectibles: ((Int64) -> [Collectible])?\n"
    "    /// PampGram: locally saved gift stickers on the GRAM card (nil = use real wallet stickers).\n"
    "    nonisolated(unsafe) public static var pampGramCardStickers: ((Int64) -> [CardSticker]?)?\n"
    "    /// PampGram: persist card stickers locally instead of the wallet API.\n"
    "    nonisolated(unsafe) public static var pampGramSaveCardStickers: ((Int64, [CardSticker]) -> Void)?\n"
    "    /// PampGram: bump the Money screen when profile gifts / local stickers change.\n"
    "    nonisolated(unsafe) public static let pampGramVisualRefreshPipe = ValuePipe<Void>()\n"
    "    public static func pampGramNotifyVisualRefresh() {\n"
    "        WalletContext.pampGramVisualRefreshPipe.putNext(Void())\n"
    "    }\n"
    "    /// PampGram: the account this wallet belongs to (the overrides are per account).\n"
    "    let pampGramAccountKey: Int64\n"
    "\n"
    "    static func pampGramApply(_ state: State, accountKey: Int64) -> State {\n"
    "        guard let override = WalletContext.pampGramBalanceOverride, let balance = override(accountKey) else {\n"
    "            return state\n"
    "        }\n"
    "        var phase = state.phase\n"
    "        var walletAddress = state.walletAddress\n"
    "        if case .empty = state.phase, let address = WalletContext.pampGramAddressOverride?(accountKey) {\n"
    "            phase = .wallet(WalletInfo(address: address, publicKey: \"\"))\n"
    "            walletAddress = address\n"
    "        }\n"
    "        switch phase {\n"
    "        case .wallet, .restoring:\n"
    "            break\n"
    "        default:\n"
    "            return state\n"
    "        }\n"
    "        var transactions = state.transactions\n"
    "        if let fake = WalletContext.pampGramTransactionsOverride?(accountKey), !fake.isEmpty {\n"
    "            var merged = fake\n"
    "            let fakeIds = Set(fake.map(\\.id))\n"
    "            for item in state.transactions.items where !fakeIds.contains(item.id) {\n"
    "                merged.append(item)\n"
    "            }\n"
    "            merged.sort(by: { $0.timestamp > $1.timestamp })\n"
    "            transactions = TransactionsState(items: merged, offset: state.transactions.offset, canLoadMore: state.transactions.canLoadMore, isLoadingMore: false, error: nil)\n"
    "        }\n"
    "        var collectibles = state.collectibles\n"
    "        if let profileGifts = WalletContext.pampGramProfileCollectibles?(accountKey), !profileGifts.isEmpty {\n"
    "            var items = collectibles.items\n"
    "            var seen = Set(items.map { $0.address.lowercased() })\n"
    "            for gift in profileGifts {\n"
    "                let key = gift.address.lowercased()\n"
    "                if seen.insert(key).inserted {\n"
    "                    items.append(gift)\n"
    "                }\n"
    "            }\n"
    "            collectibles = CollectiblesState(\n"
    "                items: items,\n"
    "                nextOffset: collectibles.nextOffset,\n"
    "                generation: collectibles.generation,\n"
    "                isRefreshing: false,\n"
    "                isLoadingMore: false,\n"
    "                error: nil\n"
    "            )\n"
    "        }\n"
    "        let cardStickers = WalletContext.pampGramCardStickers?(accountKey) ?? state.cardStickers\n"
    "        return State(\n"
    "            phase: phase,\n"
    "            walletAddress: walletAddress,\n"
    "            balance: .value(balance, updatedAt: Int32(Date().timeIntervalSince1970)),\n"
    "            transactions: transactions,\n"
    "            collectibles: collectibles,\n"
    "            pendingTransfers: state.pendingTransfers,\n"
    "            activeOperation: state.activeOperation,\n"
    "            fiat: state.fiat,\n"
    "            gaslessInfo: state.gaslessInfo,\n"
    "            cardStickers: cardStickers,\n"
    "            cardStickerChangesPending: false,\n"
    "            isSavingCardStickers: false,\n"
    "            cardStickerSaveError: nil\n"
    "        )\n"
    "    }\n"
    "\n",
)
replace_once(
    wallet_swift,
    "wallet state signal override",
    "            let disposable = (self.output.statePromise.get()\n"
    "            |> deliverOnMainQueue).start(next: subscriber.putNext)",
    "            let disposable = (combineLatest(\n"
    "                self.output.statePromise.get(),\n"
    "                (.single(Void()) |> then(WalletContext.pampGramVisualRefreshPipe.signal()))\n"
    "            )\n"
    "            |> map { state, _ in WalletContext.pampGramApply(state, accountKey: self.pampGramAccountKey) }\n"
    "            |> deliverOnMainQueue).start(next: subscriber.putNext)",
)
replace_once(
    wallet_swift,
    "wallet state value override",
    "        self.output.currentState()\n",
    "        WalletContext.pampGramApply(self.output.currentState(), accountKey: self.pampGramAccountKey)\n",
)
replace_once(
    wallet_swift,
    "wallet remembers its account",
    "        let operationTaskRegistry = WalletOperationTaskRegistry()\n",
    "        self.pampGramAccountKey = engine.account.peerId.toInt64()\n"
    "        let operationTaskRegistry = WalletOperationTaskRegistry()\n",
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
    # The root controller belongs to the active account, so the override follows account
    # switches: each new root controller re-binds it to its own account's settings.
    "        let pampGramAccountKey = self.context.account.peerId.toInt64()\n"
    "        PampGramVisualExtrasRuntime.shared.start(accountKey: pampGramAccountKey, postbox: self.context.account.postbox)\n"
    "        PampGramWalletCardStickersRuntime.shared.start(context: self.context)\n"
    "        PampGramVisualExtrasRuntime.notifyWalletRefresh = {\n"
    "            WalletContext.pampGramNotifyVisualRefresh()\n"
    "        }\n"
    "        WalletContext.pampGramBalanceOverride = { walletAccountKey in\n"
    "            return PampGramVisualExtrasRuntime.shared.fakeBalanceNanos(accountKey: walletAccountKey)\n"
    "        }\n"
    "        WalletContext.pampGramAddressOverride = { walletAccountKey in\n"
    "            return PampGramVisualExtrasRuntime.shared.fakeWalletAddress(accountKey: walletAccountKey)\n"
    "        }\n"
    "        WalletContext.pampGramProfileCollectibles = { walletAccountKey in\n"
    "            return PampGramWalletCardStickersRuntime.shared.collectibles(accountKey: walletAccountKey)\n"
    "        }\n"
    "        WalletContext.pampGramCardStickers = { walletAccountKey in\n"
    "            guard PampGramVisualExtrasRuntime.shared.fakeBalanceNanos(accountKey: walletAccountKey) != nil else {\n"
    "                return nil\n"
    "            }\n"
    "            return PampGramWalletCardStickersRuntime.shared.stickers(accountKey: walletAccountKey)\n"
    "        }\n"
    "        WalletContext.pampGramSaveCardStickers = { [weak self] walletAccountKey, stickers in\n"
    "            guard let self else {\n"
    "                return\n"
    "            }\n"
    "            PampGramWalletCardStickersRuntime.shared.setStickers(stickers, accountKey: walletAccountKey, postbox: self.context.account.postbox)\n"
    "        }\n"
    "        WalletContext.pampGramTransactionsOverride = { walletAccountKey in\n"
    "            let items = PampGramVisualExtrasRuntime.shared.walletTransactions(accountKey: walletAccountKey)\n"
    "            guard !items.isEmpty else {\n"
    "                return nil\n"
    "            }\n"
    "            return items.map { item in\n"
    "                let direction: WalletContext.Transaction.Direction = item.isIncoming ? .incoming : .outgoing\n"
    "                let peer: WalletContext.Transaction.Peer\n"
    "                switch item.kind {\n"
    "                case .topUp:\n"
    "                    peer = .onramp(address: item.address, domain: nil, providerName: item.peerTitle)\n"
    "                case .withdraw:\n"
    "                    peer = .address(item.address.isEmpty ? item.peerTitle : item.address, domain: nil)\n"
    "                case .send, .receive:\n"
    "                    peer = .onramp(address: item.address, domain: nil, providerName: item.peerTitle)\n"
    "                }\n"
    "                return WalletContext.Transaction(\n"
    "                    id: \"pampgram-\\(item.id)\",\n"
    "                    transactionHash: item.txHash.replacingOccurrences(of: \" \", with: \"\"),\n"
    "                    logicalTime: \"\\(item.date)\",\n"
    "                    timestamp: item.date,\n"
    "                    direction: direction,\n"
    "                    amount: abs(item.amountNanos),\n"
    "                    fee: 0,\n"
    "                    peer: peer,\n"
    "                    comment: nil\n"
    "                )\n"
    "            }\n"
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
    "                if let pampGramFileId = PampGramVisualExtrasRuntime.shared.verificationFileId(accountKey: self.context.account.peerId.toInt64()) {\n"
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
# 11. Visual crafting on Telegram's own craft screen: for a local visual gift the screen's list
#     of the user's gifts and the craft itself are answered locally (PhantomGiftKit), through
#     two hooks on CraftGiftsContext installed by TelegramRootController.
# ---------------------------------------------------------------------------
print("\n[11] Visual crafting on the original craft screen")

star_gifts_swift = Path("submodules/TelegramCore/Sources/TelegramEngine/Payments/StarGifts.swift")
replace_once(
    star_gifts_swift,
    "craft context local gifts hook",
    "    public var state: Signal<CraftGiftsContext.State, NoError> {\n"
    "        return Signal { subscriber in\n",
    "    /// PampGram: local data source for crafting a visual gift (nil = use the server).\n"
    "    nonisolated(unsafe) public static var pampGramLocalGifts: ((Int64) -> Signal<[ProfileGiftsContext.State.StarGift], NoError>?)?\n"
    "    /// PampGram: local craft for a visual gift (nil = use the server).\n"
    "    nonisolated(unsafe) public static var pampGramLocalCraft: ((Int64, [StarGiftReference]) -> Signal<ProfileGiftsContext.State.StarGift, CraftStarGiftError>?)?\n"
    "\n"
    "    public var state: Signal<CraftGiftsContext.State, NoError> {\n"
    "        if let pampGramLocal = CraftGiftsContext.pampGramLocalGifts?(self.giftId) {\n"
    "            return pampGramLocal\n"
    "            |> map { gifts -> CraftGiftsContext.State in\n"
    "                return CraftGiftsContext.State(gifts: gifts, count: Int32(gifts.count), dataState: .ready(canLoadMore: false, nextOffset: nil))\n"
    "            }\n"
    "        }\n"
    "        return Signal { subscriber in\n",
)
replace_once(
    star_gifts_swift,
    "craft context local craft hook",
    "    public func craft(references: [StarGiftReference]) -> Signal<ProfileGiftsContext.State.StarGift, CraftStarGiftError> {\n",
    "    public func craft(references: [StarGiftReference]) -> Signal<ProfileGiftsContext.State.StarGift, CraftStarGiftError> {\n"
    "        if let pampGramLocal = CraftGiftsContext.pampGramLocalCraft?(self.giftId, references) {\n"
    "            return pampGramLocal\n"
    "        }\n",
)
replace_once(
    gift_view_swift,
    "craft screen opened for a visual gift",
    "                let craftScreen = self.context.sharedContext.makeGiftCraftScreen(\n",
    "                if arguments.reference == nil {\n"
    "                    PampGramPhantomCraftMarker.shared.begin(giftId: gift.giftId)\n"
    "                } else {\n"
    "                    PampGramPhantomCraftMarker.shared.end()\n"
    "                }\n"
    "                let craftScreen = self.context.sharedContext.makeGiftCraftScreen(\n",
)
replace_once(
    root_swift,
    "root controller craft hooks",
    "        tabBarController.pampGramTripleTap = {",
    "        let pampGramCraftContext: AccountContext = self.context\n"
    "        CraftGiftsContext.pampGramLocalGifts = { [weak pampGramCraftContext] giftId in\n"
    "            guard let pampGramCraftContext, PampGramPhantomCraftMarker.shared.isActive(giftId: giftId) else {\n"
    "                return nil\n"
    "            }\n"
    "            return PampGramPhantomGiftManager.craftCandidates(context: pampGramCraftContext, giftId: giftId)\n"
    "        }\n"
    "        CraftGiftsContext.pampGramLocalCraft = { [weak pampGramCraftContext] giftId, references in\n"
    "            guard let pampGramCraftContext, PampGramPhantomCraftMarker.shared.isActive(giftId: giftId) else {\n"
    "                return nil\n"
    "            }\n"
    "            return PampGramPhantomGiftManager.craftLocally(context: pampGramCraftContext, giftId: giftId, references: references)\n"
    "        }\n"
    "        tabBarController.pampGramTripleTap = {",
)
replace_once(
    root_swift,
    "root controller PhantomGiftKit import",
    "import PampGramCore\nimport WalletContext\n",
    "import PampGramCore\nimport WalletContext\nimport PhantomGiftKit\n",
)

# ---------------------------------------------------------------------------
# 12. The profile "Balance" chip and the card it opens come from the server's public wallet
#     card (CachedUserData.walletCard), not from the wallet itself: substitute the visual
#     balance there too, on your own profile.
# ---------------------------------------------------------------------------
print("\n[12] Visual balance on the profile chip and the public wallet card")

replace_once(
    header_swift,
    "profile balance chip shows the visual balance",
    "        if !self.isSettings, let balance = (screenData?.cachedData as? CachedUserData)?.walletCard?.balance, balance >= 100_000_000 {\n",
    "        PampGramVisualExtrasRuntime.shared.start(accountKey: self.context.account.peerId.toInt64(), postbox: self.context.account.postbox)\n"
    "        if !self.isSettings, peer?.id == self.context.account.peerId, let pampGramFakeBalance = PampGramVisualExtrasRuntime.shared.fakeBalanceNanos(accountKey: self.context.account.peerId.toInt64()) {\n"
    "            currentWalletBalance = pampGramFakeBalance\n"
    "        } else if !self.isSettings, let balance = (screenData?.cachedData as? CachedUserData)?.walletCard?.balance, balance >= 100_000_000 {\n",
)
peer_info_screen_swift = Path("submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift")
replace_once(
    peer_info_screen_swift,
    "own visual GRAM wallet opens Money from the profile chip",
    "        self.headerNode.openWallet = { [weak self] in\n"
    "            guard let self, let controller = self.controller, let peer = self.data?.peer else { return }\n",
    "        self.headerNode.openWallet = { [weak self] in\n"
    "            guard let self, let controller = self.controller, let peer = self.data?.peer else { return }\n"
    "            // PampGram: own visual GRAM wallet is one thing — open the same Money screen\n"
    "            // («Деньги») from the profile chip, not a separate public PeerWallet card.\n"
    "            if peer.id == self.context.account.peerId,\n"
    "               PampGramVisualExtrasRuntime.shared.fakeBalanceNanos(accountKey: self.context.account.peerId.toInt64()) != nil {\n"
    "                guard WalletConfiguration.with(appConfiguration: self.context.currentAppConfiguration.with { $0 }).isAvailable else {\n"
    "                    self.openSettings(section: .wallet)\n"
    "                    return\n"
    "                }\n"
    "                controller.push(self.context.sharedContext.makeWalletScreen(context: self.context))\n"
    "                return\n"
    "            }\n",
)
replace_once(
    peer_info_screen_swift,
    "public wallet card opened from the chip shows the visual balance",
    "            let screen = PeerWalletScreen(context: self.context, updatedPresentationData: controller.updatedPresentationData, peer: peer, card: (self.data?.cachedData as? CachedUserData)?.walletCard, sourceView:",
    "            let pampGramRealCard = (self.data?.cachedData as? CachedUserData)?.walletCard\n"
    "            var pampGramCard = pampGramRealCard\n"
    "            if peer.id == self.context.account.peerId, let pampGramFakeBalance = PampGramVisualExtrasRuntime.shared.fakeBalanceNanos(accountKey: self.context.account.peerId.toInt64()) {\n"
    "                let pampGramAddress = pampGramRealCard?.address ?? (PampGramVisualExtrasRuntime.shared.fakeWalletAddress(accountKey: self.context.account.peerId.toInt64()) ?? \"\")\n"
    "                pampGramCard = WalletCard(address: pampGramAddress, balance: pampGramFakeBalance, stickers: pampGramRealCard?.stickers ?? [], backgroundNft: pampGramRealCard?.backgroundNft)\n"
    "            }\n"
    "            let screen = PeerWalletScreen(context: self.context, updatedPresentationData: controller.updatedPresentationData, peer: peer, card: pampGramCard, sourceView:",
)

# ---------------------------------------------------------------------------
# 13. Log in with a bot token when adding an account: a new TelegramCore function
#     (auth.importBotAuthorization, generated from the schema at build time) and a "Бот" button
#     on the phone-entry screen that asks for the token.
# ---------------------------------------------------------------------------
print("\n[13] Bot-token login on the phone-entry screen")

import shutil
shutil.copyfile(
    Path(__file__).resolve().parent / "hooks-sources" / "PampGramBotAuthorization.swift",
    Path("submodules/TelegramCore/Sources/PampGramBotAuthorization.swift"),
)
print("  OK: TelegramCore bot authorization source")

phone_entry_swift = Path("submodules/AuthorizationUI/Sources/AuthorizationSequencePhoneEntryController.swift")
replace_once(
    phone_entry_swift,
    "phone entry bot-token property",
    "    var accountUpdated: ((UnauthorizedAccount) -> Void)?\n",
    "    var accountUpdated: ((UnauthorizedAccount) -> Void)?\n"
    "    var pampGramLoginWithBotToken: ((String) -> Void)?\n",
)
replace_once(
    phone_entry_swift,
    "phone entry bot-token button",
    "        if !otherAccountPhoneNumbers.1.isEmpty {\n"
    "            self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: \"___close\", style: .plain, target: self, action: #selector(self.cancelPressed))\n"
    "        }\n",
    "        if !otherAccountPhoneNumbers.1.isEmpty {\n"
    "            self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: \"___close\", style: .plain, target: self, action: #selector(self.cancelPressed))\n"
    "        }\n"
    "        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: \"Бот\", style: .plain, target: self, action: #selector(self.pampGramBotTokenPressed))\n",
)
replace_once(
    phone_entry_swift,
    "phone entry bot-token prompt",
    "    @objc private func cancelPressed() {\n",
    "    @objc private func pampGramBotTokenPressed() {\n"
    "        let alert = UIAlertController(title: \"Вход по токену бота\", message: \"Вставьте токен бота из @BotFather (вида 123456:ABC…).\", preferredStyle: .alert)\n"
    "        alert.addTextField { field in\n"
    "            field.placeholder = \"123456789:AA…\"\n"
    "            field.autocorrectionType = .no\n"
    "            field.autocapitalizationType = .none\n"
    "        }\n"
    "        alert.addAction(UIAlertAction(title: \"Отмена\", style: .cancel, handler: nil))\n"
    "        alert.addAction(UIAlertAction(title: \"Войти\", style: .default, handler: { [weak self, weak alert] _ in\n"
    "            let token = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? \"\"\n"
    "            if !token.isEmpty {\n"
    "                self?.pampGramLoginWithBotToken?(token)\n"
    "            }\n"
    "        }))\n"
    "        self.present(alert, animated: true, completion: nil)\n"
    "    }\n"
    "\n"
    "    func pampGramShowBotTokenError(_ text: String) {\n"
    "        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)\n"
    "        alert.addAction(UIAlertAction(title: \"OK\", style: .default, handler: nil))\n"
    "        self.present(alert, animated: true, completion: nil)\n"
    "    }\n"
    "\n"
    "    @objc private func cancelPressed() {\n",
)
replace_once(
    Path("submodules/AuthorizationUI/Sources/AuthorizationSequenceController.swift"),
    "authorization sequence bot-token login",
    "            controller.loginWithNumber = { [weak self, weak controller] number, syncContacts in\n",
    "            controller.pampGramLoginWithBotToken = { [weak self, weak controller] token in\n"
    "                guard let self else {\n"
    "                    return\n"
    "                }\n"
    "                controller?.inProgress = true\n"
    "                let _ = (authorizeWithBotToken(accountManager: self.sharedContext.accountManager, account: self.account, token: token)\n"
    "                |> deliverOnMainQueue).startStandalone(error: { [weak controller] error in\n"
    "                    controller?.inProgress = false\n"
    "                    let text: String\n"
    "                    switch error {\n"
    "                    case .invalidToken:\n"
    "                        text = \"Неверный токен бота.\"\n"
    "                    case .limitExceeded:\n"
    "                        text = \"Слишком много попыток. Попробуйте позже.\"\n"
    "                    case .generic:\n"
    "                        text = \"Не удалось войти по токену бота.\"\n"
    "                    }\n"
    "                    controller?.pampGramShowBotTokenError(text)\n"
    "                }, completed: { [weak controller] in\n"
    "                    controller?.inProgress = false\n"
    "                })\n"
    "            }\n"
    "            controller.loginWithNumber = { [weak self, weak controller] number, syncContacts in\n",
)

# ---------------------------------------------------------------------------
# 14. The public wallet card screen (opened from the profile chip) keeps re-reading the server
#     card; substitute the visual balance every time it updates, on your own card.
# ---------------------------------------------------------------------------
print("\n[14] Visual balance on the public wallet card screen")

peer_wallet_build = Path("submodules/TelegramUI/Components/Wallet/PeerWalletScreen/BUILD")
peer_wallet_swift = Path("submodules/TelegramUI/Components/Wallet/PeerWalletScreen/Sources/PeerWalletScreen.swift")
add_dep_if_missing(peer_wallet_build, "PeerWalletScreen BUILD dep", '"//submodules/AccountContext"')
add_import_if_missing(peer_wallet_swift, "PeerWalletScreen import PampGramCore", "import AccountContext\n")
replace_once(
    peer_wallet_swift,
    "peer wallet card shows the visual balance",
    "        private func updateCard(_ card: WalletCard?, context: AccountContext) {\n",
    "        private func updateCard(_ card: WalletCard?, context: AccountContext) {\n"
    "            var card = card\n"
    "            if self.peer.id == context.account.peerId, let pampGramFakeBalance = PampGramVisualExtrasRuntime.shared.fakeBalanceNanos(accountKey: context.account.peerId.toInt64()) {\n"
    "                let pampGramAddress = card?.address ?? (PampGramVisualExtrasRuntime.shared.fakeWalletAddress(accountKey: context.account.peerId.toInt64()) ?? \"\")\n"
    "                card = WalletCard(address: pampGramAddress, balance: pampGramFakeBalance, stickers: card?.stickers ?? [], backgroundNft: card?.backgroundNft)\n"
    "            }\n",
)
replace_once(
    peer_wallet_swift,
    "peer wallet refreshes visual balance from WalletContext",
    "                    if self.fiatCurrency != state.fiat.selectedCurrency || self.fiatRate != state.fiat.selectedRate || self.hasOwnWallet != hasOwnWallet {\n"
    "                        self.fiatCurrency = state.fiat.selectedCurrency\n"
    "                        self.fiatRate = state.fiat.selectedRate\n"
    "                        self.hasOwnWallet = hasOwnWallet\n"
    "                        self.updated(transition: .immediate)\n"
    "                    }\n",
    "                    var needsUpdate = self.fiatCurrency != state.fiat.selectedCurrency || self.fiatRate != state.fiat.selectedRate || self.hasOwnWallet != hasOwnWallet\n"
    "                    if needsUpdate {\n"
    "                        self.fiatCurrency = state.fiat.selectedCurrency\n"
    "                        self.fiatRate = state.fiat.selectedRate\n"
    "                        self.hasOwnWallet = hasOwnWallet\n"
    "                    }\n"
    "                    // PampGram: same GRAM wallet as Money — refresh visual balance whenever\n"
    "                    // WalletContext re-applies (settings amount / top-up / send).\n"
    "                    if self.peer.id == context.account.peerId,\n"
    "                       PampGramVisualExtrasRuntime.shared.fakeBalanceNanos(accountKey: context.account.peerId.toInt64()) != nil {\n"
    "                        let previousBalance = self.card?.balance\n"
    "                        self.updateCard(self.card, context: context)\n"
    "                        if self.card?.balance != previousBalance {\n"
    "                            needsUpdate = true\n"
    "                        }\n"
    "                    }\n"
    "                    if needsUpdate {\n"
    "                        self.updated(transition: .immediate)\n"
    "                    }\n",
)

# ---------------------------------------------------------------------------
# 15. Visual wallet send / top-up: when «Карточка GRAM» is on, Money's «Отправить» and
#     «Пополнить» stay local instead of opening the real transfer / receive flows.
# ---------------------------------------------------------------------------
print("\n[15] Visual wallet send/top-up intercept on WalletScreen")

wallet_screen_build = Path("submodules/TelegramUI/Components/Wallet/WalletScreen/BUILD")
wallet_screen_swift = Path("submodules/TelegramUI/Components/Wallet/WalletScreen/Sources/WalletScreen.swift")
# add_dep_if_missing only knows how to insert PampGramCore; insert SettingsUI by hand.
_ws_build = wallet_screen_build.read_text()
_ws_dep = '"//submodules/TelegramUI/Components/PampGram/PampGramSettingsUI"'
if _ws_dep not in _ws_build:
    _ws_anchor = '"//submodules/AccountContext",'
    if _ws_anchor not in _ws_build:
        # Fall back: append near the end of deps if AccountContext isn't listed that way.
        _ws_anchor = "deps = ["
    if _ws_anchor not in _ws_build:
        print("FAIL [WalletScreen BUILD]: cannot find deps anchor", file=sys.stderr)
        sys.exit(1)
    _idx = _ws_build.index(_ws_anchor) + len(_ws_anchor)
    wallet_screen_build.write_text(_ws_build[:_idx] + "\n        " + _ws_dep + "," + _ws_build[_idx:])
    print("  OK: WalletScreen BUILD dep PampGramSettingsUI")
else:
    print("  SKIP: WalletScreen BUILD dep PampGramSettingsUI (already present)")
_ws_swift = wallet_screen_swift.read_text()
if "import PampGramSettingsUI" not in _ws_swift:
    _imp_anchor = "import WalletSendScreen\n"
    if _imp_anchor not in _ws_swift:
        print("FAIL [WalletScreen import]: anchor not found", file=sys.stderr)
        sys.exit(1)
    _idx = _ws_swift.index(_imp_anchor) + len(_imp_anchor)
    wallet_screen_swift.write_text(_ws_swift[:_idx] + "import PampGramSettingsUI\n" + _ws_swift[_idx:])
    print("  OK: WalletScreen import PampGramSettingsUI")
else:
    print("  SKIP: WalletScreen import PampGramSettingsUI (already present)")
replace_once(
    wallet_screen_swift,
    "visual wallet intercept openReceive",
    "        private func openReceive() {\n",
    "        private func openReceive() {\n"
    "            if let component = self.component, pampGramVisualWalletIsActive(context: component.context) {\n"
    "                pampGramPresentVisualWalletTopUp(context: component.context, presenter: self.environment?.controller())\n"
    "                return\n"
    "            }\n",
)
replace_once(
    wallet_screen_swift,
    "visual wallet intercept openSend",
    "        private func openSend(address: String? = nil) {\n",
    "        private func openSend(address: String? = nil) {\n"
    "            if let component = self.component, pampGramVisualWalletIsActive(context: component.context) {\n"
    "                pampGramPresentVisualWalletSend(context: component.context, presenter: self.environment?.controller())\n"
    "                return\n"
    "            }\n",
)

# ---------------------------------------------------------------------------
# 16. Chat ⋯ menu: «Отправить деньги» / «Получить GRAM в чат» for the visual wallet.
# ---------------------------------------------------------------------------
print("\n[16] Visual wallet actions in the chat more menu")

chat_open_peer = Path("submodules/TelegramUI/Sources/Chat/ChatControllerOpenPeer.swift")
_cop = chat_open_peer.read_text()
if "import PampGramSettingsUI" not in _cop:
    _cop_anchor = "import PampGramCore\n"
    if _cop_anchor not in _cop:
        print("FAIL [ChatControllerOpenPeer import]: PampGramCore import missing", file=sys.stderr)
        sys.exit(1)
    _idx = _cop.index(_cop_anchor) + len(_cop_anchor)
    chat_open_peer.write_text(_cop[:_idx] + "import PampGramSettingsUI\n" + _cop[_idx:])
    print("  OK: ChatControllerOpenPeer import PampGramSettingsUI")
else:
    print("  SKIP: ChatControllerOpenPeer import PampGramSettingsUI (already present)")
replace_once(
    chat_open_peer,
    "visual wallet chat more-menu items",
    "        items.append(.action(ContextMenuActionItem(text: \"Восстановить чат\", icon: { theme in\n",
    "        items.append(.action(ContextMenuActionItem(text: \"Отправить деньги\", icon: { theme in\n"
    "            return generateTintedImage(image: UIImage(bundleImageName: \"Chat/Context Menu/Check\"), color: theme.contextMenu.primaryColor)\n"
    "        }, action: { [weak self] action in\n"
    "            action.dismissWithResult(.default)\n"
    "            guard let self else { return }\n"
    "            let presentationData = self.presentationData\n"
    "            let peerName: String\n"
    "            if let peer = self.presentationInterfaceState.renderedPeer?.peer {\n"
    "                peerName = EnginePeer(peer).displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)\n"
    "            } else {\n"
    "                peerName = \"Получатель\"\n"
    "            }\n"
    "            pampGramPresentVisualWalletSend(context: self.context, preselectedPeerId: peerId, preselectedTitle: peerName)\n"
    "        })))\n"
    "        items.append(.action(ContextMenuActionItem(text: \"Получить GRAM в чат\", icon: { theme in\n"
    "            return generateTintedImage(image: UIImage(bundleImageName: \"Chat/Context Menu/Resend\"), color: theme.contextMenu.primaryColor)\n"
    "        }, action: { [weak self] action in\n"
    "            action.dismissWithResult(.default)\n"
    "            guard let self else { return }\n"
    "            let presentationData = self.presentationData\n"
    "            let peerName: String\n"
    "            if let peer = self.presentationInterfaceState.renderedPeer?.peer {\n"
    "                peerName = EnginePeer(peer).displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)\n"
    "            } else {\n"
    "                peerName = \"Отправитель\"\n"
    "            }\n"
    "            pampGramPresentVisualWalletReceiveInChat(context: self.context, peerId: peerId, peerTitle: peerName)\n"
    "        })))\n"
    "        items.append(.action(ContextMenuActionItem(text: \"Восстановить чат\", icon: { theme in\n",
)

# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 16b. Visual GRAM card stickers: local save + skip inventory reconcile
# ---------------------------------------------------------------------------
print("\n[16b] Visual GRAM card stickers persistence")
wallet_card_stickers = Path("submodules/WalletContext/Sources/WalletCardStickers.swift")
replace_once(
    wallet_card_stickers,
    "visual card stickers local save",
    """    func updateCardStickers(_ stickers: [WalletContext.CardSticker], walletAddress: String) {
        guard !self.isShutdown, case let .wallet(info) = self.currentState.phase,
              info.address == walletAddress else { return }
        let value = WalletContext.CardSticker.validated(stickers)
""",
    """    func updateCardStickers(_ stickers: [WalletContext.CardSticker], walletAddress: String) {
        guard !self.isShutdown, case let .wallet(info) = self.currentState.phase,
              info.address == walletAddress else { return }
        let value = WalletContext.CardSticker.validated(stickers)
        // Visual GRAM card: keep stickers on-device only (profile gifts), never hit the wallet API.
        if WalletContext.pampGramBalanceOverride?(self.engine.account.peerId.toInt64()) != nil {
            self.cardStickersByWallet[walletAddress] = value
            self.cardStickerDirtyWallets.remove(walletAddress)
            self.cardStickerSaveError = nil
            WalletContext.pampGramSaveCardStickers?(self.engine.account.peerId.toInt64(), value)
            self.replaceState(
                phase: self.currentState.phase, balance: self.currentState.balance,
                transactions: self.currentState.transactions, pendingTransfers: self.currentState.pendingTransfers,
                activeOperation: self.currentState.activeOperation
            )
            return
        }
""",
)
replace_once(
    wallet_card_stickers,
    "visual card stickers skip reconcile",
    """    func reconcileCardStickers(_ collectibles: WalletContext.CollectiblesState) {
        guard !collectibles.isRefreshing, !collectibles.isLoadingMore,
              collectibles.error == nil, collectibles.nextOffset == nil,
              let address = self.currentState.walletAddress else { return }
""",
    """    func reconcileCardStickers(_ collectibles: WalletContext.CollectiblesState) {
        if WalletContext.pampGramBalanceOverride?(self.engine.account.peerId.toInt64()) != nil {
            return
        }
        guard !collectibles.isRefreshing, !collectibles.isLoadingMore,
              collectibles.error == nil, collectibles.nextOffset == nil,
              let address = self.currentState.walletAddress else { return }
""",
)

# 17. GiftOptionsScreen "Мои": own-profile visual gifts + local 25-Star transfer
# ---------------------------------------------------------------------------
print("\n[17] Visual gifts in GiftOptionsScreen Mine tab")

gift_options_build = Path("submodules/TelegramUI/Components/Gifts/GiftOptionsScreen/BUILD")
_go_build = gift_options_build.read_text()
_pgk = '"//submodules/TelegramUI/Components/PampGram/PhantomGiftKit"'
if _pgk not in _go_build:
    _anchor = '"//submodules/TelegramUI/Components/PampGram/PampGramCore",'
    if _anchor not in _go_build:
        print("FAIL [GiftOptionsScreen BUILD PhantomGiftKit]: PampGramCore dep missing", file=sys.stderr)
        sys.exit(1)
    _idx = _go_build.index(_anchor) + len(_anchor)
    gift_options_build.write_text(_go_build[:_idx] + "\n        " + _pgk + "," + _go_build[_idx:])
    print("  OK: GiftOptionsScreen BUILD PhantomGiftKit")
else:
    print("  SKIP: GiftOptionsScreen BUILD PhantomGiftKit (already present)")

gift_options_swift = Path(
    "submodules/TelegramUI/Components/Gifts/GiftOptionsScreen/Sources/GiftOptionsScreen.swift"
)
_gos = gift_options_swift.read_text()
if "import PhantomGiftKit\n" not in _gos:
    if "import PampGramCore\n" not in _gos:
        print("FAIL [GiftOptionsScreen import PhantomGiftKit]: PampGramCore import missing", file=sys.stderr)
        sys.exit(1)
    _idx = _gos.index("import PampGramCore\n") + len("import PampGramCore\n")
    gift_options_swift.write_text(_gos[:_idx] + "import PhantomGiftKit\n" + _gos[_idx:])
    print("  OK: GiftOptionsScreen import PhantomGiftKit")
else:
    print("  SKIP: GiftOptionsScreen import PhantomGiftKit (already present)")

# Signal first so the merge below can reference pampGramProfileGifts.
replace_once(
    gift_options_swift,
    "Mine tab watches visual profile gifts",
    """                availableProducts,
                context.engine.payments.cachedStarGifts(),
                self.starGiftsContext.state
            ).start(next: { [weak self] peer, disallowedGifts, availableProducts, starGifts, profileGiftsState in
""",
    """                availableProducts,
                context.engine.payments.cachedStarGifts(),
                self.starGiftsContext.state,
                // Own-profile visual gifts — the same list the profile grid shows after
                // "Подарок мне" / a self-send — so the "Мои" tab can transfer them for ⭐25.
                PampGramPhantomGiftStore.resolvedProfileGiftsSignal(context: context)
            ).start(next: { [weak self] peer, disallowedGifts, availableProducts, starGifts, profileGiftsState, pampGramProfileGifts in
""",
)
replace_once(
    gift_options_swift,
    "Mine tab merges own-profile visual gifts",
    """                        self.transferStarGifts = profileGiftsState.filteredGifts.compactMap { gift in
                            if case .unique = gift.gift {
                                return gift
                            } else {
                                return nil
                            }
                        }
""",
    """                        var transferGifts = profileGiftsState.filteredGifts.compactMap { gift -> ProfileGiftsContext.State.StarGift? in
                            if case .unique = gift.gift {
                                return gift
                            } else {
                                return nil
                            }
                        }
                        var seenSlugs = Set(transferGifts.compactMap { gift -> String? in
                            if case let .unique(unique) = gift.gift {
                                return unique.slug
                            }
                            return nil
                        })
                        for phantom in pampGramProfileGifts {
                            guard case let .unique(unique) = phantom.gift else {
                                continue
                            }
                            if seenSlugs.contains(unique.slug) {
                                continue
                            }
                            seenSlugs.insert(unique.slug)
                            transferGifts.append(phantom)
                        }
                        self.transferStarGifts = transferGifts
""",
)
replace_once(
    gift_options_swift,
    "Mine tab transferGift allows visual gifts",
    """            guard let gift = self.state?.transferStarGifts?.first(where: { gift in
                if case let .unique(gift) = gift.gift, gift.slug == transferGift.slug {
                    return true
                } else {
                    return false
                }
            }), let reference = gift.reference else {
                return
            }
""",
    """            guard let gift = self.state?.transferStarGifts?.first(where: { gift in
                if case let .unique(gift) = gift.gift, gift.slug == transferGift.slug {
                    return true
                } else {
                    return false
                }
            }) else {
                return
            }
            // Visual gifts from the own profile have no server reference — transfer them
            // locally for the same 25-Star fee as "Передать" on the profile card.
            let pampGramIsPhantomGift = gift.reference == nil
            let reference = gift.reference
""",
)
replace_once(
    gift_options_swift,
    "Mine tab transfer alert uses 25-Star visual fee",
    """            let alertController = giftTransferAlertController(
                context: context,
                gift: transferGift,
                peer: peer,
                transferStars: gift.transferStars ?? 0,
                navigationController: mainController.navigationController as? NavigationController,
                commit: { [weak self, weak mainController] in
                    let proceed: (Bool) -> Void = { waitForTopUp in
                        var errorImpl: ((TransferStarGiftError) -> Void)?
                        var completedImpl: (() -> Void)?
                        
                        if waitForTopUp, let starsContext = context.starsContext {
                            let _ = (starsContext.onUpdate
                            |> deliverOnMainQueue).start(next: {
                                let _ = (context.engine.payments.transferStarGift(prepaid: gift.transferStars == 0, reference: reference, peerId: peer.id)
                                |> deliverOnMainQueue).start(error: { error in
                                    errorImpl?(error)
                                }, completed: {
                                    completedImpl?()
                                })
                            })
                        } else {
                            let _ = (context.engine.payments.transferStarGift(prepaid: gift.transferStars == 0, reference: reference, peerId: peer.id)
                            |> deliverOnMainQueue).start(error: { error in
                                errorImpl?(error)
                            }, completed: {
                                completedImpl?()
                            })
                        }
""",
    """            let pampGramTransferStars: Int64 = pampGramIsPhantomGift ? PampGramPhantomGiftManager.transferFeeStars : (gift.transferStars ?? 0)
            if pampGramIsPhantomGift {
                PampGramPhantomGiftManager.markPhantomTransfer(slug: transferGift.slug)
            }
            let alertController = giftTransferAlertController(
                context: context,
                gift: transferGift,
                peer: peer,
                transferStars: pampGramTransferStars,
                navigationController: mainController.navigationController as? NavigationController,
                commit: { [weak self, weak mainController] in
                    let proceed: (Bool) -> Void = { waitForTopUp in
                        var errorImpl: ((TransferStarGiftError) -> Void)?
                        var completedImpl: (() -> Void)?
                        
                        if pampGramIsPhantomGift {
                            let _ = (PampGramPhantomGiftManager.sendUniqueGiftToPeer(context: context, uniqueGift: transferGift, peerId: peer.id)
                            |> deliverOnMainQueue).start(next: { success in
                                if success {
                                    completedImpl?()
                                } else {
                                    errorImpl?(.generic)
                                }
                            })
                        } else if let reference {
                            if waitForTopUp, let starsContext = context.starsContext {
                                let _ = (starsContext.onUpdate
                                |> deliverOnMainQueue).start(next: {
                                    let _ = (context.engine.payments.transferStarGift(prepaid: gift.transferStars == 0, reference: reference, peerId: peer.id)
                                    |> deliverOnMainQueue).start(error: { error in
                                        errorImpl?(error)
                                    }, completed: {
                                        completedImpl?()
                                    })
                                })
                            } else {
                                let _ = (context.engine.payments.transferStarGift(prepaid: gift.transferStars == 0, reference: reference, peerId: peer.id)
                                |> deliverOnMainQueue).start(error: { error in
                                    errorImpl?(error)
                                }, completed: {
                                    completedImpl?()
                                })
                            }
                        } else {
                            errorImpl?(.generic)
                        }
""",
)
replace_once(
    gift_options_swift,
    "Mine tab skips real Stars check for visual gifts",
    """                    if let self, let transferStars = gift.transferStars, transferStars > 0, let starsContext = context.starsContext, let starsState = self.starsState {
                        if starsState.balance < StarsAmount(value: transferStars, nanos: 0) {
                            let _ = (self.optionsPromise.get()
                            |> filter { $0 != nil }
                            |> take(1)
                            |> deliverOnMainQueue).startStandalone(next: { [weak mainController] options in
                                let purchaseController = context.sharedContext.makeStarsPurchaseScreen(
                                    context: context,
                                    starsContext: starsContext,
                                    options: options ?? [],
                                    purpose: .transferStarGift(requiredStars: transferStars),
                                    targetPeerId: nil,
                                    customTheme: nil,
                                    completion: { stars in
                                        starsContext.add(balance: StarsAmount(value: stars, nanos: 0))
                                        proceed(true)
                                    }
                                )
                                mainController?.push(purchaseController)
                            })
                        } else {
                            proceed(false)
                        }
                    } else {
                        proceed(false)
                    }
""",
    """                    if pampGramIsPhantomGift {
                        let _ = (PampGramPhantomGiftManager.canAffordTransferFee(context: context)
                        |> deliverOnMainQueue).startStandalone(next: { [weak mainController] canAfford in
                            if canAfford {
                                proceed(false)
                            } else {
                                let alertController = textAlertController(
                                    context: context,
                                    title: "Недостаточно Stars",
                                    text: "Передача подарка стоит \\(PampGramPhantomGiftManager.transferFeeStars) ⭐.",
                                    actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                                )
                                mainController?.present(alertController, in: .window(.root))
                            }
                        })
                    } else if let self, let transferStars = gift.transferStars, transferStars > 0, let starsContext = context.starsContext, let starsState = self.starsState {
                        if starsState.balance < StarsAmount(value: transferStars, nanos: 0) {
                            let _ = (self.optionsPromise.get()
                            |> filter { $0 != nil }
                            |> take(1)
                            |> deliverOnMainQueue).startStandalone(next: { [weak mainController] options in
                                let purchaseController = context.sharedContext.makeStarsPurchaseScreen(
                                    context: context,
                                    starsContext: starsContext,
                                    options: options ?? [],
                                    purpose: .transferStarGift(requiredStars: transferStars),
                                    targetPeerId: nil,
                                    customTheme: nil,
                                    completion: { stars in
                                        starsContext.add(balance: StarsAmount(value: stars, nanos: 0))
                                        proceed(true)
                                    }
                                )
                                mainController?.push(purchaseController)
                            })
                        } else {
                            proceed(false)
                        }
                    } else {
                        proceed(false)
                    }
""",
)

# ---------------------------------------------------------------------------
# 18. Chat title: stable visual Premium star (no jump on chat open)
# ---------------------------------------------------------------------------
print("\n[18] Chat title stable local Premium badge")
chat_title_build = Path("submodules/TelegramUI/Components/ChatTitleView/BUILD")
if '"//submodules/TelegramUI/Components/PampGram/PhantomGiftKit"' not in chat_title_build.read_text():
    text = chat_title_build.read_text()
    anchor = '"//submodules/TelegramUI/Components/AnimatedTextComponent",'
    if anchor not in text:
        print("FAIL [ChatTitleView BUILD PhantomGiftKit]: anchor missing", file=sys.stderr)
        sys.exit(1)
    idx = text.index(anchor) + len(anchor)
    chat_title_build.write_text(
        text[:idx] + '\n        "//submodules/TelegramUI/Components/PampGram/PhantomGiftKit",' + text[idx:]
    )
    print("  OK: ChatTitleView BUILD PhantomGiftKit")
else:
    print("  SKIP: ChatTitleView BUILD PhantomGiftKit (already present)")

for chat_title_src, label, after_import in [
    (
        Path("submodules/TelegramUI/Components/ChatTitleView/Sources/ChatTitleView.swift"),
        "ChatTitleView import PhantomGiftKit",
        "import AnimatedTextComponent\n",
    ),
    (
        Path("submodules/TelegramUI/Components/ChatTitleView/Sources/ChatTitleComponent.swift"),
        "ChatTitleComponent import PhantomGiftKit",
        "import NewsFeedSupport\n",
    ),
]:
    text = chat_title_src.read_text()
    if "import PhantomGiftKit" in text:
        print(f"  SKIP: {label} (already present)")
    elif after_import not in text:
        print(f"FAIL [{label}]: import anchor missing", file=sys.stderr)
        sys.exit(1)
    else:
        idx = text.index(after_import) + len(after_import)
        chat_title_src.write_text(text[:idx] + "import PhantomGiftKit\n" + text[idx:])
        print(f"  OK: {label}")

replace_once(
    Path("submodules/TelegramUI/Components/ChatTitleView/Sources/ChatTitleView.swift"),
    "ChatTitleView local premium badge",
    "                                    } else if peer.isPremium && !premiumConfiguration.isPremiumDisabled {\n"
    "                                        titleCredibilityIcon = .premium\n"
    "                                    }\n",
    "                                    } else if (peer.isPremium || PampGramLocalPremiumRuntime.shared.isActive(peerId: peer.id)) && !premiumConfiguration.isPremiumDisabled {\n"
    "                                        // PampGram: keep the visual Premium star stable when Telegram\n"
    "                                        // briefly rewrites the peer without .isPremium on chat open.\n"
    "                                        titleCredibilityIcon = .premium\n"
    "                                    }\n",
)
replace_once(
    Path("submodules/TelegramUI/Components/ChatTitleView/Sources/ChatTitleComponent.swift"),
    "ChatTitleComponent local premium badge",
    "                            } else if peer.isPremium && !premiumConfiguration.isPremiumDisabled {\n"
    "                                titleCredibilityIcon = .premium\n"
    "                            }\n",
    "                            } else if (peer.isPremium || PampGramLocalPremiumRuntime.shared.isActive(peerId: peer.id)) && !premiumConfiguration.isPremiumDisabled {\n"
    "                                // PampGram: stable visual Premium star (see ChatTitleView).\n"
    "                                titleCredibilityIcon = .premium\n"
    "                            }\n",
)

# ---------------------------------------------------------------------------
# 19. Premium gift cards: no discount ribbons; prices always in ₽
# ---------------------------------------------------------------------------
print("\n[19] Premium gift cards: no ribbons, RUB prices")
gift_options_src = Path(
    "submodules/TelegramUI/Components/Gifts/GiftOptionsScreen/Sources/GiftOptionsScreen.swift"
)
replace_once(
    gift_options_src,
    "premium gift ribbon removed",
    "                            ribbon: product.discount.flatMap {\n"
    "                                GiftItemComponent.Ribbon(\n"
    '                                    text:  "-\\($0)%",\n'
    "                                    color: .purple\n"
    "                                )\n"
    "                            },\n",
    "                            ribbon: nil,\n",
)

gift_setup_src = Path(
    "submodules/TelegramUI/Components/Gifts/GiftSetupScreen/Sources/GiftSetupScreen.swift"
)
replace_once(
    gift_setup_src,
    "premium price always RUB",
    """    public var price: String {
        return self.storeProduct?.price ?? formatCurrencyAmount(self.giftOption.amount, currency: self.giftOption.currency)
    }
""",
    """    /// PampGram: currency/amount actually charged and shown on the gift bubble — always RUB
    /// when we can convert, never the stock preview fallback `("USD", 1)` ($0.01).
    public var pampGramChargeCurrencyAndAmount: (currency: String, amount: Int64) {
        if self.giftOption.currency.uppercased() == "RUB", self.giftOption.amount > 0 {
            return ("RUB", self.giftOption.amount)
        }
        if let storeProduct = self.storeProduct {
            let (currency, amount) = storeProduct.priceCurrencyAndAmount
            if currency.uppercased() == "RUB" {
                return ("RUB", amount)
            }
            let major = Double(amount) / 100.0
            let rate: Double
            switch currency.uppercased() {
            case "EUR":
                rate = 100.0
            case "USD":
                rate = 95.0
            default:
                rate = 95.0
            }
            let kopecks = Int64((major * rate * 100.0).rounded())
            return ("RUB", max(kopecks, 1))
        }
        if self.giftOption.amount > 0 {
            let currency = self.giftOption.currency.uppercased()
            if currency == "RUB" {
                return ("RUB", self.giftOption.amount)
            }
            let major = Double(self.giftOption.amount) / 100.0
            let kopecks = Int64((major * 95.0 * 100.0).rounded())
            return ("RUB", max(kopecks, 1))
        }
        return ("RUB", max(self.giftOption.amount, 1))
    }

    /// PampGram: always show Premium gift prices in rubles (cards + send button), never App Store $.
    public var price: String {
        let (currency, amount) = self.pampGramChargeCurrencyAndAmount
        return formatCurrencyAmount(amount, currency: currency)
    }
""",
)

# ---------------------------------------------------------------------------
print("\nPampGram: feature hooks done.")
print("  ACTIVE: ChatTimeMachine, VideoMessageSaver, FakeBadge, FakeSubscribers, FakeDeletedAccount")
print("  CONTEXT MENU ONLY: FakeForward, FakeReactions, FakeActivity, InvisibleMessage, ReactionSpammer,")
print("    FakeSystemMessages, FakePaymentReceipt, FakeIncomingCall, FakeScreenshotNotification, VisualWallet")
print("  MINE TAB: visual gifts from own profile transfer for ⭐25")
print("  PREMIUM: RUB prices, no ribbons; visual Stars on Pay-with-Stars footer")
