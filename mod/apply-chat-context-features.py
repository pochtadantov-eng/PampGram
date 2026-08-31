#!/usr/bin/env python3
"""Apply PampGram context-menu/copy-protection integration after the base patch.

This file intentionally replaces the old overlapping unified-diff block from
telegram-ios-features.patch. The base PampGram patch and the features patch both
edit ChatInterfaceStateContextMenus.swift; applying two diffs to the same wrapper
made the second patch fail after the v8 local-message/history additions. These
semantic replacements run against the already base-patched source and fail loudly
if upstream/base state is not what we expect.
"""
from pathlib import Path
import sys

path = Path("submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift")
text = path.read_text()


def replace_once(label: str, old: str, new: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        print(f"PampGram post-patch failed [{label}]: expected 1 match, found {count}", file=sys.stderr)
        sys.exit(1)
    text = text.replace(old, new, 1)
    print(f"OK: {label}")

replace_once(
    "share one settings signal with the wrapper",
    """    let baseItems = contextMenuForChatPresentationInterfaceStateReal(chatPresentationInterfaceState: chatPresentationInterfaceState, context: context, messages: messages, controllerInteraction: controllerInteraction, selectAll: selectAll, interfaceInteraction: interfaceInteraction, readStats: readStats, messageNode: messageNode)\n""",
    """    let settingsSignal = PampGramCore.settingsSignal(postbox: context.account.postbox)\n    let baseItems = settingsSignal\n    |> map { settings in\n        return contextMenuForChatPresentationInterfaceStateReal(chatPresentationInterfaceState: chatPresentationInterfaceState, context: context, messages: messages, controllerInteraction: controllerInteraction, selectAll: selectAll, interfaceInteraction: interfaceInteraction, readStats: readStats, messageNode: messageNode, copyProtectionBypassEnabled: settings.copyProtectionBypassEnabled)\n    }\n    |> switchToLatest\n""",
)

replace_once(
    "reuse settings signal for PampGram message menu",
    """    return combineLatest(baseItems, PampGramCore.settingsSignal(postbox: context.account.postbox))\n""",
    """    return combineLatest(baseItems, settingsSignal)\n""",
)

replace_once(
    "pass copy-protection bypass into stock menu builder",
    """private func contextMenuForChatPresentationInterfaceStateReal(chatPresentationInterfaceState: ChatPresentationInterfaceState, context: AccountContext, messages: [EngineRawMessage], controllerInteraction: ChatControllerInteraction?, selectAll: Bool, interfaceInteraction: ChatPanelInterfaceInteraction?, readStats: MessageReadStats? = nil, messageNode: ChatMessageItemView? = nil) -> Signal<ContextController.Items, NoError> {\n""",
    """private func contextMenuForChatPresentationInterfaceStateReal(chatPresentationInterfaceState: ChatPresentationInterfaceState, context: AccountContext, messages: [EngineRawMessage], controllerInteraction: ChatControllerInteraction?, selectAll: Bool, interfaceInteraction: ChatPanelInterfaceInteraction?, readStats: MessageReadStats? = nil, messageNode: ChatMessageItemView? = nil, copyProtectionBypassEnabled: Bool = false) -> Signal<ContextController.Items, NoError> {\n""",
)

replace_once(
    "allow replying when copy-protection bypass applies",
    """    if !canSendMessagesToChat(chatPresentationInterfaceState) && (chatPresentationInterfaceState.copyProtectionEnabled || message.isCopyProtected()) {\n        canReply = false\n    }\n""",
    """    let copyProtectionBypassApplies = copyProtectionBypassEnabled && message.id.peerId.namespace != Namespaces.Peer.SecretChat && !message.containsSecretMedia\n    if !canSendMessagesToChat(chatPresentationInterfaceState) && !copyProtectionBypassApplies && (chatPresentationInterfaceState.copyProtectionEnabled || message.isCopyProtected()) {\n        canReply = false\n    }\n""",
)

replace_once(
    "expose actions as unprotected when bypass applies",
    """                isCopyProtected: messageActions.isCopyProtected,\n""",
    """                isCopyProtected: copyProtectionBypassApplies ? false : messageActions.isCopyProtected,\n""",
)

replace_once(
    "menu copy-protection state",
    """        let isCopyProtected = chatPresentationInterfaceState.copyProtectionEnabled || message.isCopyProtected()\n""",
    """        let isCopyProtected = !copyProtectionBypassApplies && (chatPresentationInterfaceState.copyProtectionEnabled || message.isCopyProtected())\n""",
)

replace_once(
    "show forward action under bypass",
    """        if data.messageActions.options.contains(.forward) {\n""",
    """        if data.messageActions.options.contains(.forward) || (copyProtectionBypassApplies && !isAction) {\n""",
)

replace_once(
    "subscribe to PampGram settings for available actions",
    """func chatAvailableMessageActionsImpl(engine: TelegramEngine, accountPeerId: EnginePeer.Id, messageIds: Set<EngineMessage.Id>, messages: [EngineMessage.Id: EngineRawMessage] = [:], peers: [EnginePeer.Id: EngineRawPeer] = [:], keepUpdated: Bool) -> Signal<ChatAvailableMessageActions, NoError> {\n    return engine.data.subscribe(\n""",
    """func chatAvailableMessageActionsImpl(engine: TelegramEngine, accountPeerId: EnginePeer.Id, messageIds: Set<EngineMessage.Id>, messages: [EngineMessage.Id: EngineRawMessage] = [:], peers: [EnginePeer.Id: EngineRawPeer] = [:], keepUpdated: Bool) -> Signal<ChatAvailableMessageActions, NoError> {\n    let baseDataSignal = engine.data.subscribe(\n""",
)

replace_once(
    "combine available-actions data with PampGram settings",
    """    |> take(keepUpdated ? Int.max : 1)\n    |> map { limitsConfiguration, peerMap, messageMap, copyProtectionMap, myCopyProtectionMap, accountPeer -> ChatAvailableMessageActions in\n""",
    """    |> take(keepUpdated ? Int.max : 1)\n\n    let baseSignal = combineLatest(baseDataSignal, PampGramCore.settingsSignal(postbox: engine.account.postbox))\n    |> map { data, settings -> ChatAvailableMessageActions in\n        let (limitsConfiguration, peerMap, messageMap, copyProtectionMap, myCopyProtectionMap, accountPeer) = data\n""",
)

replace_once(
    "message copy protection test",
    """                if message.isCopyProtected() || message.containsSecretMedia {\n                    isCopyProtected = true\n                }\n                \n                if isPeerCopyProtected(message.id.peerId) == true {\n                    isCopyProtected = true\n                }\n""",
    """                let copyProtectionBypassApplies = settings.copyProtectionBypassEnabled && message.id.peerId.namespace != Namespaces.Peer.SecretChat && !message.containsSecretMedia\n                if (!copyProtectionBypassApplies && message.isCopyProtected()) || message.containsSecretMedia {\n                    isCopyProtected = true\n                }\n                \n                if !copyProtectionBypassApplies && isPeerCopyProtected(message.id.peerId) == true {\n                    isCopyProtected = true\n                }\n""",
)

replace_once(
    "forward option for channel messages",
    """                            if message.id.peerId.namespace != Namespaces.Peer.SecretChat && !message.isCopyProtected() {\n""",
    """                            if message.id.peerId.namespace != Namespaces.Peer.SecretChat && (copyProtectionBypassApplies || !message.isCopyProtected()) {\n""",
)

replace_once(
    "forward option for groups",
    """                            if !isAction && !message.isCopyProtected() && !isShareProtected {\n""",
    """                            if !isAction && (copyProtectionBypassApplies || !message.isCopyProtected()) && !isShareProtected {\n""",
)

replace_once(
    "forward option for users",
    """                        if !isScheduled && message.id.peerId.namespace != Namespaces.Peer.SecretChat && !message.containsSecretMedia && !isAction && !message.id.peerId.isReplies && !message.isCopyProtected() && !isShareProtected {\n""",
    """                        if !isScheduled && message.id.peerId.namespace != Namespaces.Peer.SecretChat && !message.containsSecretMedia && !isAction && !message.id.peerId.isReplies && (copyProtectionBypassApplies || !message.isCopyProtected()) && !isShareProtected {\n""",
)

# Anchor this final insertion on the exact tail of chatAvailableMessageActionsImpl,
# immediately before ChatDeleteMessageContextItem. This avoids touching unrelated closures.
replace_once(
    "return combined available-actions signal",
    """            return ChatAvailableMessageActions(options: [], banAuthor: nil, banAuthors: [], disableDelete: false, isCopyProtected: isCopyProtected, setTag: false, editTags: Set())\n        }\n    }\n}\n\nfinal class ChatDeleteMessageContextItem: ContextMenuCustomItem {\n""",
    """            return ChatAvailableMessageActions(options: [], banAuthor: nil, banAuthors: [], disableDelete: false, isCopyProtected: isCopyProtected, setTag: false, editTags: Set())\n        }\n    }\n\n    return baseSignal\n}\n\nfinal class ChatDeleteMessageContextItem: ContextMenuCustomItem {\n""",
)

path.write_text(text)
print("PampGram: ChatInterfaceStateContextMenus post-patch integration complete.")
