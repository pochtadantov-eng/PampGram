import Foundation
import UIKit
import AVFoundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PampGramCore
import UndoUI

private final class PampGramCallRecordingArguments {
    let toggleEnabled: (Bool) -> Void
    let openRecording: (PampGramCallRecordingEntry) -> Void
    let deleteAll: () -> Void

    init(toggleEnabled: @escaping (Bool) -> Void, openRecording: @escaping (PampGramCallRecordingEntry) -> Void, deleteAll: @escaping () -> Void) {
        self.toggleEnabled = toggleEnabled
        self.openRecording = openRecording
        self.deleteAll = deleteAll
    }
}

private enum PampGramCallRecordingSection: Int32 {
    case about
    case main
    case list
}

private enum PampGramCallRecordingEntryItem: ItemListNodeEntry {
    case about(String)
    case enabled(Bool)
    case footer(String)
    case listHeader(String)
    case empty(String)
    case recording(Int32, PampGramCallRecordingEntry)
    case deleteAll

    var section: ItemListSectionId {
        switch self {
        case .about:
            return PampGramCallRecordingSection.about.rawValue
        case .enabled, .footer:
            return PampGramCallRecordingSection.main.rawValue
        case .listHeader, .empty, .recording, .deleteAll:
            return PampGramCallRecordingSection.list.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .about: return 0
        case .enabled: return 1
        case .footer: return 2
        case .listHeader: return 3
        case .empty: return 4
        case let .recording(index, _): return 10 + index
        case .deleteAll: return 100000
        }
    }

    static func <(lhs: PampGramCallRecordingEntryItem, rhs: PampGramCallRecordingEntryItem) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramCallRecordingArguments
        switch self {
        case let .about(text), let .footer(text), let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .enabled(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "record.circle.fill", backgroundColor: UIColor(rgb: 0xff3b30)), title: "Записывать звонки", value: value, enableInteractiveChanges: false, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleEnabled(value)
            })
        case let .listHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .recording(_, recording):
            let date = pampGramCallRecordingDateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(recording.date)))
            let direction = recording.isOutgoing ? "исходящий" : "входящий"
            let title = recording.title.isEmpty ? "Звонок" : recording.title
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: recording.isOutgoing ? "phone.arrow.up.right.fill" : "phone.arrow.down.left.fill", backgroundColor: UIColor(rgb: recording.isOutgoing ? 0x34c759 : 0x007aff)), title: title, label: pampGramCallRecordingDuration(recording.duration), additionalDetailLabel: "\(date) · \(direction)", sectionId: self.section, style: .blocks, action: {
                arguments.openRecording(recording)
            })
        case .deleteAll:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Удалить все записи", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.deleteAll()
            })
        }
    }
}

private let pampGramCallRecordingDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "dd.MM.yyyy HH:mm"
    return formatter
}()

private func pampGramCallRecordingDuration(_ duration: Double) -> String {
    let total = max(0, Int(duration.rounded()))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
}

private func pampGramCallRecordingSize(_ bytes: Int64) -> String {
    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private func pampGramCallRecordingEntries(enabled: Bool, recordings: [PampGramCallRecordingEntry], size: Int64) -> [PampGramCallRecordingEntryItem] {
    var entries: [PampGramCallRecordingEntryItem] = []
    entries.append(.about("Когда включено, PampGram записывает обычные (не групповые) звонки: ваш голос и голос собеседника сохраняются в один аудиофайл. Запись начинается, когда звонок соединился, и заканчивается вместе со звонком."))
    entries.append(.enabled(enabled))
    entries.append(.footer("Файлы хранятся только на этом телефоне, никуда не отправляются и не попадают в резервную копию. Собеседник не получает никакого уведомления, что звонок записывается. Во многих странах запись разговора без согласия второй стороны запрещена, поэтому предупреждайте собеседника и используйте запись только с его согласия."))
    entries.append(.listHeader(recordings.isEmpty ? "ЗАПИСИ" : "ЗАПИСИ · \(recordings.count) · \(pampGramCallRecordingSize(size))"))
    if recordings.isEmpty {
        entries.append(.empty("Пока нет записей. Включите запись и позвоните — после звонка запись появится здесь."))
    } else {
        for (index, recording) in recordings.enumerated() {
            entries.append(.recording(Int32(index), recording))
        }
        entries.append(.deleteAll)
    }
    return entries
}

private final class PampGramCallRecordingPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private(set) var playingId: String?
    var onFinished: (() -> Void)?

    func toggle(id: String) -> Bool {
        if self.playingId == id {
            self.stop()
            return false
        }
        self.stop()
        let url = PampGramCallRecordingStore.fileURL(id: id)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            if player.play() {
                self.player = player
                self.playingId = id
                return true
            }
        } catch {
        }
        return false
    }

    func stop() {
        self.player?.stop()
        self.player = nil
        self.playingId = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.player = nil
        self.playingId = nil
        self.onFinished?()
    }
}

public func pampGramCallRecordingController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentActivityImpl: ((UIActivityViewController) -> Void)?
    var presentTooltipImpl: ((String) -> Void)?

    let reload = ValuePromise<Int>(0, ignoreRepeated: false)
    var reloadCounter = 0
    let triggerReload: () -> Void = {
        reloadCounter += 1
        reload.set(reloadCounter)
    }

    let player = PampGramCallRecordingPlayer()
    player.onFinished = {
        Queue.mainQueue().async {
            triggerReload()
        }
    }

    func updateSettings(_ f: @escaping (inout PampGramSettings) -> Void) {
        let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
            var settings = settings
            f(&settings)
            return settings
        }).start()
    }

    let arguments = PampGramCallRecordingArguments(
        toggleEnabled: { value in
            if !value {
                updateSettings { $0.callRecordingEnabled = false }
                return
            }
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            presentControllerImpl?(textAlertController(
                context: context,
                title: "Включить запись звонков?",
                text: "Собеседник не будет знать, что разговор записывается. Запись чужого голоса без согласия может быть незаконной там, где вы живёте. Включайте только если собеседник согласен. Записи останутся на этом телефоне.",
                actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .defaultAction, title: "Включить", action: {
                        updateSettings { $0.callRecordingEnabled = true }
                    })
                ]
            ))
        },
        openRecording: { recording in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: presentationData)
            let title = recording.title.isEmpty ? "Звонок" : recording.title
            let isPlaying = player.playingId == recording.id
            sheet.setItemGroups([
                ActionSheetItemGroup(items: [
                    ActionSheetTextItem(title: "\(title) · \(pampGramCallRecordingDuration(recording.duration))"),
                    ActionSheetButtonItem(title: isPlaying ? "Остановить" : "Воспроизвести", color: .accent, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        if !player.toggle(id: recording.id) && !isPlaying {
                            presentTooltipImpl?("Не удалось воспроизвести запись.")
                        }
                    }),
                    ActionSheetButtonItem(title: "Поделиться", color: .accent, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        player.stop()
                        let url = PampGramCallRecordingStore.fileURL(id: recording.id)
                        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                        presentActivityImpl?(activity)
                    }),
                    ActionSheetButtonItem(title: "Удалить", color: .destructive, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        if player.playingId == recording.id {
                            player.stop()
                        }
                        PampGramCallRecordingStore.remove(id: recording.id)
                        triggerReload()
                    })
                ]),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(sheet)
        },
        deleteAll: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            presentControllerImpl?(textAlertController(
                context: context,
                title: "Удалить все записи?",
                text: "Все записанные звонки будут удалены с телефона без возможности восстановления.",
                actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .destructiveAction, title: "Удалить", action: {
                        player.stop()
                        PampGramCallRecordingStore.removeAll()
                        triggerReload()
                    })
                ]
            ))
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.rawSettingsSignal(postbox: context.account.postbox),
        reload.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let recordings = PampGramCallRecordingStore.entries()
        let size = PampGramCallRecordingStore.totalSize()
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Запись звонков"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramCallRecordingEntries(enabled: settings.callRecordingEnabled, recordings: recordings, size: size),
            style: .blocks,
            animateChanges: false
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.didDisappear = { _ in
        player.stop()
    }
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    presentActivityImpl = { [weak controller] activity in
        guard let controller else { return }
        activity.popoverPresentationController?.sourceView = controller.view
        activity.popoverPresentationController?.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1.0, height: 1.0)
        controller.present(activity, animated: true, completion: nil)
    }
    presentTooltipImpl = { [weak controller] text in
        guard let controller else { return }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }
    return controller
}
