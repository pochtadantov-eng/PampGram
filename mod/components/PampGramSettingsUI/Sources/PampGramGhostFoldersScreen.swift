import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PampGramCore

private final class PampGramGhostFoldersArguments {
    let toggleFolder: (Int32, Bool) -> Void

    init(toggleFolder: @escaping (Int32, Bool) -> Void) {
        self.toggleFolder = toggleFolder
    }
}

private enum PampGramGhostFoldersSection: Int32 {
    case about
    case folders
}

private enum PampGramGhostFoldersEntry: ItemListNodeEntry {
    case aboutText(String)
    case foldersHeader(String)
    case folder(Int, Int32, String, Bool)
    case foldersEmpty(String)

    var section: ItemListSectionId {
        switch self {
        case .aboutText:
            return PampGramGhostFoldersSection.about.rawValue
        case .foldersHeader, .folder, .foldersEmpty:
            return PampGramGhostFoldersSection.folders.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .aboutText:
            return 0
        case .foldersHeader:
            return 1
        case .foldersEmpty:
            return 2
        case let .folder(index, _, _, _):
            return 100 + Int32(index)
        }
    }

    static func ==(lhs: PampGramGhostFoldersEntry, rhs: PampGramGhostFoldersEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.aboutText(lhsText), .aboutText(rhsText)):
            return lhsText == rhsText
        case let (.foldersHeader(lhsText), .foldersHeader(rhsText)):
            return lhsText == rhsText
        case let (.foldersEmpty(lhsText), .foldersEmpty(rhsText)):
            return lhsText == rhsText
        case let (.folder(lhsIndex, lhsId, lhsTitle, lhsValue), .folder(rhsIndex, rhsId, rhsTitle, rhsValue)):
            return lhsIndex == rhsIndex && lhsId == rhsId && lhsTitle == rhsTitle && lhsValue == rhsValue
        default:
            return false
        }
    }

    static func <(lhs: PampGramGhostFoldersEntry, rhs: PampGramGhostFoldersEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramGhostFoldersArguments
        switch self {
        case let .aboutText(text), let .foldersEmpty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .foldersHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .folder(_, id, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleFolder(id, value)
            })
        }
    }
}

private func pampGramGhostFoldersEntries(folders: [(Int32, String)], excludedFolderIds: [Int32]) -> [PampGramGhostFoldersEntry] {
    var entries: [PampGramGhostFoldersEntry] = []

    entries.append(.aboutText("Режим призрака не действует в чатах, добавленных вручную в выбранные папки."))
    entries.append(.foldersHeader("ПАПКИ"))
    if folders.isEmpty {
        entries.append(.foldersEmpty("У вас пока нет папок с чатами."))
    } else {
        for (index, folder) in folders.enumerated() {
            entries.append(.folder(index, folder.0, folder.1, excludedFolderIds.contains(folder.0)))
        }
    }

    return entries
}

/// Reached from "Режим призрака" → "Папки" — chat folders whose manually-added chats are
/// exempt from Ghost, stored in `PampGramSettings.ghostExcludedFolderIds` and resolved by
/// `pampGramGhostFolderIds` in TelegramCore.
public func pampGramGhostFoldersController(context: AccountContext) -> ViewController {
    let arguments = PampGramGhostFoldersArguments(
        toggleFolder: { folderId, value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                var current = settings.ghostExcludedFolderIds
                if value {
                    if !current.contains(folderId) {
                        current.append(folderId)
                    }
                } else {
                    current.removeAll(where: { $0 == folderId })
                }
                settings.ghostExcludedFolderIds = current
                return settings
            }).start()
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.rawSettingsSignal(postbox: context.account.postbox),
        context.engine.peers.updatedChatListFilters()
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, filters -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var folders: [(Int32, String)] = []
        for filter in filters {
            if case let .filter(id, title, _, _) = filter {
                folders.append((id, title.text))
            }
        }
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Папки"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramGhostFoldersEntries(folders: folders, excludedFolderIds: settings.ghostExcludedFolderIds),
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    return controller
}
