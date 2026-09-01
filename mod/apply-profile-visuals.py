#!/usr/bin/env python3
"""Apply PampGram's local profile visuals after the base Telegram patch.

The base patch owns the PampGram entry in Telegram's Settings. This small,
anchor-checked post-patch adds the presentation layer to the ordinary profile
screen, where Telegram keeps its profile-item construction in a separate file.
It deliberately fails loudly if Telegram changes that layout.
"""

from pathlib import Path
import sys


def replace_once(path: Path, label: str, old: str, new: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        print(
            f"PampGram profile-visuals post-patch failed [{label}]: "
            f"expected 1 match, found {count}",
            file=sys.stderr,
        )
        sys.exit(1)
    path.write_text(text.replace(old, new, 1))
    print(f"OK: {label}")


def replace_count(path: Path, label: str, old: str, new: str, expected_count: int) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != expected_count:
        print(
            f"PampGram profile-visuals post-patch failed [{label}]: "
            f"expected {expected_count} matches, found {count}",
            file=sys.stderr,
        )
        sys.exit(1)
    path.write_text(text.replace(old, new))
    print(f"OK: {label}")


screen_path = Path(
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift"
)
profile_items_path = Path(
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoProfileItems.swift"
)
header_path = Path(
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift"
)

replace_once(
    screen_path,
    "store live profile-visual state",
    """    var pampGramSettings = PampGramSettings.defaultSettings
    var pampGramSettingsDisposable: Disposable?

""",
    """    var pampGramSettings = PampGramSettings.defaultSettings
    var pampGramSettingsDisposable: Disposable?

    // Separate from the general settings: this state is rendered only in the
    // current account's own profile and never changes Telegram server data.
    var pampGramProfileVisuals = PampGramProfileVisualState.default
    var pampGramProfileVisualsDisposable: Disposable?

""",
)

replace_once(
    screen_path,
    "observe profile-visual state",
    """        self.pampGramSettingsDisposable = (PampGramCore.settingsSignal(postbox: context.account.postbox)
        |> deliverOnMainQueue).startStrict(next: { [weak self] settings in
            guard let self else {
                return
            }
            self.pampGramSettings = settings
            self.requestLayout(animated: false)
        })
    }

    deinit {
""",
    """        self.pampGramSettingsDisposable = (PampGramCore.settingsSignal(postbox: context.account.postbox)
        |> deliverOnMainQueue).startStrict(next: { [weak self] settings in
            guard let self else {
                return
            }
            self.pampGramSettings = settings
            self.requestLayout(animated: false)
        })

        self.pampGramProfileVisualsDisposable = (PampGramProfileVisualStore.signal(postbox: context.account.postbox)
        |> deliverOnMainQueue).startStrict(next: { [weak self] state in
            guard let self else {
                return
            }
            self.pampGramProfileVisuals = state
            self.requestLayout(animated: false)
        })
    }

    deinit {
""",
)

replace_once(
    screen_path,
    "dispose profile-visual subscription",
    """    deinit {
        self.pampGramSettingsDisposable?.dispose()
        self.dataDisposable?.dispose()
""",
    """    deinit {
        self.pampGramSettingsDisposable?.dispose()
        self.pampGramProfileVisualsDisposable?.dispose()
        self.dataDisposable?.dispose()
""",
)

replace_once(
    screen_path,
    "pass visuals to profile items",
    """            let items = self.isSettings ? settingsItems(data: self.data, context: self.context, presentationData: self.presentationData, interaction: self.interaction, isExpanded: self.headerNode.isAvatarExpanded, pampGramSettings: self.pampGramSettings) : infoItems(data: self.data, context: self.context, presentationData: self.presentationData, interaction: self.interaction, reactionSourceMessageId: self.reactionSourceMessageId, canDeleteReaction: self.canDeleteReaction, callMessages: self.callMessages, chatLocation: self.chatLocation, isOpenedFromChat: self.isOpenedFromChat, isMyProfile: self.isMyProfile)
""",
    """            let items = self.isSettings ? settingsItems(data: self.data, context: self.context, presentationData: self.presentationData, interaction: self.interaction, isExpanded: self.headerNode.isAvatarExpanded, pampGramSettings: self.pampGramSettings) : infoItems(data: self.data, context: self.context, presentationData: self.presentationData, interaction: self.interaction, reactionSourceMessageId: self.reactionSourceMessageId, canDeleteReaction: self.canDeleteReaction, callMessages: self.callMessages, chatLocation: self.chatLocation, isOpenedFromChat: self.isOpenedFromChat, isMyProfile: self.isMyProfile, pampGramProfileVisuals: self.pampGramProfileVisuals)
""",
)

replace_count(
    screen_path,
    "pass visuals to the profile header",
    """isContact: self.data?.isContact ?? false, isSettings: self.isSettings, state: self.state,""",
    """isContact: self.data?.isContact ?? false, isSettings: self.isSettings, pampGramProfileVisuals: self.pampGramProfileVisuals, state: self.state,""",
    2,
)

replace_once(
    header_path,
    "import profile state into the profile header",
    """import EdgeEffect
""",
    """import EdgeEffect
import PampGramCore
""",
)

replace_once(
    header_path,
    "accept visuals in profile-header layout",
    """isSecretChat: Bool, isContact: Bool, isSettings: Bool, state: PeerInfoState,""",
    """isSecretChat: Bool, isContact: Bool, isSettings: Bool, pampGramProfileVisuals: PampGramProfileVisualState, state: PeerInfoState,""",
)

replace_once(
    header_path,
    "prefer visual rating over the server rating badge",
    """        #endif
        
        if let starRating = self.currentStarRating {
""",
    """        #endif

        // The preference is intentionally used only for the account owner's ordinary
        // profile. Settings and every remote profile continue showing Telegram data.
        let isUsingVisualRating = self.isMyProfile && !isSettings && pampGramProfileVisuals.ratingEnabled
        let visualRating: TelegramStarRating?
        if isUsingVisualRating {
            let level = Int32(max(Int64(1), min(Int64(100), pampGramProfileVisuals.ratingValue)))
            let stars = max(Int64(0), pampGramProfileVisuals.ratingPoints)
            visualRating = TelegramStarRating(
                level: level,
                currentLevelStars: 0,
                stars: stars,
                nextLevelStars: stars < Int64.max ? stars + 1 : nil
            )
        } else {
            visualRating = nil
        }

        let displayedRating = visualRating ?? self.currentStarRating
        if let starRating = displayedRating {
""",
)

replace_once(
    header_path,
    "keep visual badge from opening the server rating screen",
    """                    action: { [weak self] in
                        guard let self, let peer = self.peer, let currentStarRating = self.currentStarRating else {
""",
    """                    action: { [weak self] in
                        guard !isUsingVisualRating else {
                            return
                        }
                        guard let self, let peer = self.peer, let currentStarRating = self.currentStarRating else {
""",
)

replace_once(
    profile_items_path,
    "import PampGramCore for profile state",
    """import PeerNameColorItem
import BoostLevelIconComponent

""",
    """import PeerNameColorItem
import BoostLevelIconComponent
import PampGramCore

""",
)

replace_once(
    profile_items_path,
    "create a dedicated local profile section",
    """    case personalChannel
    case peerInfo
    case balances
""",
    """    case personalChannel
    case peerInfo
    case pampGramProfile
    case balances
""",
)

replace_once(
    profile_items_path,
    "accept profile-visual state",
    """    chatLocation: ChatLocation,
    isOpenedFromChat: Bool,
    isMyProfile: Bool
) -> [(AnyHashable, [PeerInfoScreenItem])] {
""",
    """    chatLocation: ChatLocation,
    isOpenedFromChat: Bool,
    isMyProfile: Bool,
    pampGramProfileVisuals: PampGramProfileVisualState
) -> [(AnyHashable, [PeerInfoScreenItem])] {
""",
)

replace_once(
    profile_items_path,
    "reserve local profile item identifiers",
    """        let ItemVerification = 9004
        let ItemCommunity = 10000
        
""",
    """        let ItemVerification = 9004
        let ItemCommunity = 10000
        let ItemPampGramRating = 11002
        
""",
)

replace_once(
    profile_items_path,
    "replace the own-profile phone number locally",
    """        if let phone = user.phone {
            let formattedPhone = formatPhoneNumber(context: context, number: phone)
            let label: String
            if formattedPhone.hasPrefix(\"+888 \") {
                label = presentationData.strings.UserInfo_AnonymousNumberLabel
            } else {
                label = presentationData.strings.ContactInfo_PhoneLabelMobile
            }
            items[currentPeerInfoSection]!.append(PeerInfoScreenLabeledValueItem(id: ItemPhoneNumber, label: label, text: formattedPhone, textColor: .accent, action: { node, progress in
                interaction.openPhone(phone, node, nil, progress)
            }, longTapAction: nil, contextAction: { node, gesture, _ in
                interaction.openPhone(phone, node, gesture, nil)
            }, requestLayout: { animated in
                interaction.requestLayout(animated)
            }))
        }
""",
    """        if let phone = user.phone {
            // This is a local presentation choice for the account owner's profile.
            // It never changes Telegram's phone number on the server.
            if isMyProfile && pampGramProfileVisuals.anonymousNumberEnabled {
                let visualNumber = pampGramProfileVisuals.anonymousNumber
                items[currentPeerInfoSection]!.append(PeerInfoScreenLabeledValueItem(
                    id: ItemPhoneNumber,
                    label: presentationData.strings.UserInfo_AnonymousNumberLabel,
                    text: visualNumber,
                    textColor: .accent,
                    action: { node, _ in
                        // This sheet is local UI only. It never queries Fragment or Telegram.
                        let formatter = DateFormatter()
                        formatter.locale = Locale(identifier: "ru_RU")
                        formatter.dateStyle = .long
                        let date = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(pampGramProfileVisuals.anonymousNumberPurchasedAt)))
                        let price: String
                        if pampGramProfileVisuals.anonymousNumberPriceTonNanos > 0 {
                            price = String(format: "%.2f TON", Double(pampGramProfileVisuals.anonymousNumberPriceTonNanos) / 1_000_000_000.0)
                        } else {
                            price = "цена не указана"
                        }
                        let sheet = UIAlertController(
                            title: "\\(visualNumber) — коллекционный номер телефона",
                            message: "Номер \\(visualNumber) добавлен локально \\(date). Цена: \\(price).",
                            preferredStyle: .actionSheet
                        )
                        sheet.addAction(UIAlertAction(title: "Подробнее", style: .default, handler: nil))
                        sheet.addAction(UIAlertAction(title: "Копировать номер", style: .default, handler: { _ in
                            UIPasteboard.general.string = visualNumber
                        }))
                        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                        if let popover = sheet.popoverPresentationController {
                            popover.sourceView = node.view
                            popover.sourceRect = node.bounds
                        }
                        node.view.window?.rootViewController?.present(sheet, animated: true)
                    },
                    longTapAction: { _ in
                        UIPasteboard.general.string = visualNumber
                    },
                    contextAction: nil,
                    requestLayout: { animated in
                        interaction.requestLayout(animated)
                    }
                ))
            } else {
                let formattedPhone = formatPhoneNumber(context: context, number: phone)
                let label: String
                if formattedPhone.hasPrefix(\"+888 \") {
                    label = presentationData.strings.UserInfo_AnonymousNumberLabel
                } else {
                    label = presentationData.strings.ContactInfo_PhoneLabelMobile
                }
                items[currentPeerInfoSection]!.append(PeerInfoScreenLabeledValueItem(id: ItemPhoneNumber, label: label, text: formattedPhone, textColor: .accent, action: { node, progress in
                    interaction.openPhone(phone, node, nil, progress)
                }, longTapAction: nil, contextAction: { node, gesture, _ in
                    interaction.openPhone(phone, node, gesture, nil)
                }, requestLayout: { animated in
                    interaction.requestLayout(animated)
                }))
            }
        }
""",
)

replace_once(
    profile_items_path,
    "render the local visual rating in the own profile",
    """        }
        
        if !isMyProfile {
""",
    """        }

        // The rating is shown only in the account owner's profile.
        if isMyProfile && pampGramProfileVisuals.ratingEnabled {
                let visualPoints = max(Int64(0), pampGramProfileVisuals.ratingPoints)
                let pointsText: String
                if visualPoints >= 1_000_000 {
                    pointsText = String(format: "%.1fM очков", Double(visualPoints) / 1_000_000.0)
                } else if visualPoints >= 1_000 {
                    pointsText = String(format: "%.1fK очков", Double(visualPoints) / 1_000.0)
                } else {
                    pointsText = "\\(visualPoints) очков"
                }
                let level = max(Int64(1), pampGramProfileVisuals.ratingValue)
                items[.pampGramProfile]!.append(PeerInfoScreenLabeledValueItem(
                    id: ItemPampGramRating,
                    label: "Рейтинг",
                    rightLabel: pointsText,
                    text: "Уровень \\(level)",
                    textColor: .primary,
                    action: nil,
                    requestLayout: { animated in
                        interaction.requestLayout(animated)
                    }
                ))
        }
        
        if !isMyProfile {
""",
)

print("PampGram: profile visual integration complete.")
