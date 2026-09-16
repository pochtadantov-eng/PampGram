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
import Photos
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import UndoUI
import PromptUI

/// The paperclip long-press menu: builds a whole fake conversation — any mix of text, photos,
/// stickers, voice notes and files, tagged per item as "я" or "собеседник" — then drops the
/// whole thing into the real chat at once, in order, once "Отправить" is tapped. Nothing here
/// is presented as a standalone `NavigationController` (that was the earlier version's bug —
/// see the removed `PampGramVisualChatMenuController: ViewController` below). An ad-hoc
/// `NavigationController` that's never laid out through this app's real `Window`/`WindowHost`
/// never receives `containerLayoutUpdated`, so its child's view frame stays `.zero` forever —
/// a black screen, not a crash, which is why it went unnoticed until someone actually tapped
/// through it. `ItemListController`, PUSHED onto the app's own live navigation controller (the
/// exact same pattern `PampGramHubScreen`/`PampGramAdminScreen` already use successfully), sidesteps
/// the whole problem: it's driven by the same window that's already laying out the chat itself.

private struct PampGramVisualChatInterlocutor {
    let id: EnginePeer.Id
    let displayName: String
}

private enum PampGramVisualChatContent {
    case text(String)
    case photo(Media)
    case sticker(Media)
    case voice(Media, durationSeconds: Int)
    case file(Media, fileName: String)

    var icon: String {
        switch self {
        case .text: return "💬"
        case .photo: return "📷"
        case .sticker: return "🎨"
        case .voice: return "🎙"
        case .file: return "📄"
        }
    }

    var preview: String {
        switch self {
        case let .text(text):
            return text
        case .photo:
            return "Фото"
        case .sticker:
            return "Стикер"
        case let .voice(_, duration):
            return "Голосовое (\(duration) сек)"
        case let .file(_, fileName):
            return fileName
        }
    }
}

/// `ordinal` is a monotonically increasing counter assigned at add-time, never reused even
/// after a deletion — a stable identity for a draft that survives reordering, unlike an array
/// index (which a delete/reaction tap captures at render time and could go stale by the time
/// the tap handler runs if the list changed in between).
private struct PampGramVisualChatDraft {
    let ordinal: Int
    let isIncoming: Bool
    let authorId: EnginePeer.Id
    let authorLabel: String
    var content: PampGramVisualChatContent
    var reaction: String?
}

private func pampGramVisualChatInsertMessage(context: AccountContext, chatPeerId: EnginePeer.Id, authorId: EnginePeer.Id, isIncoming: Bool, timestamp: Int32, text: String, media: [Media]) -> Signal<EngineMessage.Id?, NoError> {
    return context.account.postbox.transaction { transaction -> EngineMessage.Id? in
        let globallyUniqueId = Int64.random(in: Int64.min ... Int64.max)
        let storeMessage = StoreMessage(
            id: .Partial(chatPeerId, Namespaces.Message.Local),
            customStableId: nil,
            globallyUniqueId: globallyUniqueId,
            groupingKey: nil,
            threadId: nil,
            timestamp: timestamp,
            flags: isIncoming ? StoreMessageFlags.Incoming : StoreMessageFlags(),
            tags: [],
            globalTags: [],
            localTags: [],
            forwardInfo: nil,
            authorId: authorId,
            text: text,
            attributes: [],
            media: media
        )
        let insertedIds = transaction.addMessages([storeMessage], location: .Random)
        return insertedIds[globallyUniqueId]
    }
}

private func pampGramVisualChatFakeMediaDirectory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("PampGram/FakeMedia", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func pampGramVisualChatPersistFile(data: Data, suggestedExtension: String) -> String? {
    let dir = pampGramVisualChatFakeMediaDirectory()
    let safeExtension = suggestedExtension.isEmpty ? "dat" : suggestedExtension
    let path = dir.appendingPathComponent("\(Int64.random(in: 1...Int64.max)).\(safeExtension)")
    do {
        try data.write(to: path, options: .atomic)
        return path.path
    } catch {
        return nil
    }
}

@available(iOS 14.0, *)
private func pampGramVisualChatMimeType(forExtension ext: String) -> String {
    if let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
        return mime
    }
    return "application/octet-stream"
}

/// Writes `durationSeconds` of zeroed (silent) 16-bit PCM to a local `.caf` file — no encoder
/// needed, `AVAudioFile` writes that container natively. Playback goes through this app's own
/// ffmpeg-backed `MediaPlayer`, which probes the real container rather than trusting the
/// `mimeType` string (see `pampGramVisualChatPresentFilePicker` below, which already
/// tags arbitrary picked audio files as `"audio/ogg"` regardless of their real format) — so a
/// `.caf` file plays back fine as a "voice message" that's just silence the whole way through.
private func pampGramVisualChatSynthesizeSilentVoice(durationSeconds: Double) -> String? {
    guard durationSeconds > 0 else {
        return nil
    }
    let dir = pampGramVisualChatFakeMediaDirectory()
    let fileURL = dir.appendingPathComponent("\(Int64.random(in: 1...Int64.max)).caf")

    let sampleRate = 48000.0
    guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true) else {
        return nil
    }
    guard let audioFile = try? AVAudioFile(forWriting: fileURL, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true) else {
        return nil
    }

    var remaining = Int(sampleRate * durationSeconds)
    while remaining > 0 {
        let chunk = min(remaining, Int(sampleRate))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(chunk)
        guard let _ = try? audioFile.write(from: buffer) else {
            return nil
        }
    }
    return fileURL.path
}

private func pampGramVisualChatTopController(context: AccountContext) -> ViewController? {
    return (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController as? ViewController
}

private func pampGramVisualChatTopUIViewController(context: AccountContext) -> UIViewController? {
    return (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController
}

// MARK: - Photo / sticker picker (a picked image either way — a real Telegram sticker file is
// out of scope here, this reuses the same "picked photo, different label" approach the earlier
// version of this menu already shipped for "sticker")

@available(iOS 14.0, *)
private var pampGramVisualChatActiveImagePickerDelegate: PampGramVisualChatImagePickerDelegate?

@available(iOS 14.0, *)
private final class PampGramVisualChatImagePickerDelegate: NSObject, PHPickerViewControllerDelegate {
    var completion: ((UIImage?) -> Void)?

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first, result.itemProvider.canLoadObject(ofClass: UIImage.self) else {
            self.completion?(nil)
            return
        }
        result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            let image = object as? UIImage
            DispatchQueue.main.async {
                self?.completion?(image)
            }
        }
    }
}

@available(iOS 14.0, *)
private func pampGramVisualChatPresentImagePicker(context: AccountContext, onImage: @escaping (Media) -> Void) {
    guard let presentingController = pampGramVisualChatTopUIViewController(context: context) else {
        return
    }
    let delegate = PampGramVisualChatImagePickerDelegate()
    pampGramVisualChatActiveImagePickerDelegate = delegate
    delegate.completion = { image in
        pampGramVisualChatActiveImagePickerDelegate = nil
        guard let image, let data = image.jpegData(compressionQuality: 0.9) else {
            return
        }
        guard let path = pampGramVisualChatPersistFile(data: data, suggestedExtension: "jpg") else {
            return
        }
        let pixelSize: CGSize
        if let cgImage = image.cgImage {
            pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        } else {
            pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        }
        let resource = LocalFileReferenceMediaResource(localFilePath: path, randomId: Int64.random(in: Int64.min...Int64.max), isUniquelyReferencedTemporaryFile: false, size: Int64(data.count))
        let representation = TelegramMediaImageRepresentation(dimensions: PixelDimensions(pixelSize), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)
        let media = TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: Int64.random(in: Int64.min...Int64.max)), representations: [representation], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        onImage(media)
    }

    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = 1
    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = delegate
    presentingController.present(picker, animated: true, completion: nil)
}

// MARK: - File / voice-from-file picker

private var pampGramVisualChatActiveDocumentPickerDelegate: PampGramVisualChatDocumentPickerDelegate?

private final class PampGramVisualChatDocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    var completion: ((URL) -> Void)?

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first {
            self.completion?(url)
        }
    }
}

@available(iOS 14.0, *)
private func pampGramVisualChatPresentFilePicker(context: AccountContext, asVoice: Bool, onFile: @escaping (Media, String) -> Void) {
    guard let presentingController = pampGramVisualChatTopUIViewController(context: context) else {
        return
    }
    let delegate = PampGramVisualChatDocumentPickerDelegate()
    pampGramVisualChatActiveDocumentPickerDelegate = delegate
    delegate.completion = { url in
        pampGramVisualChatActiveDocumentPickerDelegate = nil
        guard let data = try? Data(contentsOf: url) else {
            return
        }
        let originalName = url.lastPathComponent
        let ext = url.pathExtension
        guard let path = pampGramVisualChatPersistFile(data: data, suggestedExtension: ext) else {
            return
        }
        let resource = LocalFileReferenceMediaResource(localFilePath: path, randomId: Int64.random(in: Int64.min...Int64.max), isUniquelyReferencedTemporaryFile: false, size: Int64(data.count))

        var attributes: [TelegramMediaFileAttribute] = []
        if asVoice {
            let duration = Int(AVURLAsset(url: url).duration.seconds.rounded())
            attributes.append(.Audio(isVoice: true, duration: max(duration, 0), title: nil, performer: nil, waveform: nil))
        } else {
            attributes.append(.FileName(fileName: originalName))
        }

        let file = TelegramMediaFile(
            fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min...Int64.max)),
            partialReference: nil,
            resource: resource,
            previewRepresentations: [],
            videoThumbnails: [],
            immediateThumbnailData: nil,
            mimeType: asVoice ? "audio/ogg" : pampGramVisualChatMimeType(forExtension: ext),
            size: Int64(data.count),
            attributes: attributes,
            alternativeRepresentations: []
        )
        onFile(file, originalName)
    }

    let contentTypes: [UTType] = asVoice ? [.audio] : [.item]
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
    picker.delegate = delegate
    presentingController.present(picker, animated: true, completion: nil)
}

private func pampGramVisualChatBuildSilentVoiceMedia(durationSeconds: Int) -> Media? {
    guard let path = pampGramVisualChatSynthesizeSilentVoice(durationSeconds: Double(durationSeconds)) else {
        return nil
    }
    guard let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64 else {
        return nil
    }
    let resource = LocalFileReferenceMediaResource(localFilePath: path, randomId: Int64.random(in: Int64.min...Int64.max), isUniquelyReferencedTemporaryFile: false, size: size)
    return TelegramMediaFile(
        fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min...Int64.max)),
        partialReference: nil,
        resource: resource,
        previewRepresentations: [],
        videoThumbnails: [],
        immediateThumbnailData: nil,
        mimeType: "audio/ogg",
        size: size,
        attributes: [.Audio(isVoice: true, duration: durationSeconds, title: nil, performer: nil, waveform: nil)],
        alternativeRepresentations: []
    )
}

// MARK: - List screen

private enum PampGramVisualChatSection: Int32 {
    case interlocutor
    case add
    case messages
}

private enum PampGramVisualChatEntry: ItemListNodeEntry {
    case interlocutorInfo(String)
    case addHeader(String)
    case addText(String)
    case addPhoto(String)
    case addSticker(String)
    case addVoice(String)
    case addFile(String)
    case messagesHeader(String)
    case messagesEmpty(String)
    case messageRow(ordinal: Int, title: String, label: String)

    var section: ItemListSectionId {
        switch self {
        case .interlocutorInfo:
            return PampGramVisualChatSection.interlocutor.rawValue
        case .addHeader, .addText, .addPhoto, .addSticker, .addVoice, .addFile:
            return PampGramVisualChatSection.add.rawValue
        case .messagesHeader, .messagesEmpty, .messageRow:
            return PampGramVisualChatSection.messages.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .interlocutorInfo:
            return 0
        case .addHeader:
            return 1
        case .addText:
            return 2
        case .addPhoto:
            return 3
        case .addSticker:
            return 4
        case .addVoice:
            return 5
        case .addFile:
            return 6
        case .messagesHeader:
            return 7
        case .messagesEmpty:
            return 8
        case let .messageRow(ordinal, _, _):
            return Int32(1000 + ordinal)
        }
    }

    static func ==(lhs: PampGramVisualChatEntry, rhs: PampGramVisualChatEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.interlocutorInfo(lhsText), .interlocutorInfo(rhsText)):
            return lhsText == rhsText
        case let (.addHeader(lhsText), .addHeader(rhsText)):
            return lhsText == rhsText
        case let (.addText(lhsText), .addText(rhsText)):
            return lhsText == rhsText
        case let (.addPhoto(lhsText), .addPhoto(rhsText)):
            return lhsText == rhsText
        case let (.addSticker(lhsText), .addSticker(rhsText)):
            return lhsText == rhsText
        case let (.addVoice(lhsText), .addVoice(rhsText)):
            return lhsText == rhsText
        case let (.addFile(lhsText), .addFile(rhsText)):
            return lhsText == rhsText
        case let (.messagesHeader(lhsText), .messagesHeader(rhsText)):
            return lhsText == rhsText
        case let (.messagesEmpty(lhsText), .messagesEmpty(rhsText)):
            return lhsText == rhsText
        case let (.messageRow(lhsOrdinal, lhsTitle, lhsLabel), .messageRow(rhsOrdinal, rhsTitle, rhsLabel)):
            return lhsOrdinal == rhsOrdinal && lhsTitle == rhsTitle && lhsLabel == rhsLabel
        default:
            return false
        }
    }

    static func <(lhs: PampGramVisualChatEntry, rhs: PampGramVisualChatEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramVisualChatArguments
        switch self {
        case let .interlocutorInfo(text), let .addHeader(text), let .messagesHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .messagesEmpty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .addText(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addText()
            })
        case let .addPhoto(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addPhoto()
            })
        case let .addSticker(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addSticker()
            })
        case let .addVoice(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addVoice()
            })
        case let .addFile(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addFile()
            })
        case let .messageRow(ordinal, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openMessageActions(ordinal)
            })
        }
    }
}

private final class PampGramVisualChatArguments {
    let changeInterlocutor: () -> Void
    let addText: () -> Void
    let addPhoto: () -> Void
    let addSticker: () -> Void
    let addVoice: () -> Void
    let addFile: () -> Void
    let openMessageActions: (Int) -> Void
    let sendAll: () -> Void

    init(changeInterlocutor: @escaping () -> Void, addText: @escaping () -> Void, addPhoto: @escaping () -> Void, addSticker: @escaping () -> Void, addVoice: @escaping () -> Void, addFile: @escaping () -> Void, openMessageActions: @escaping (Int) -> Void, sendAll: @escaping () -> Void) {
        self.changeInterlocutor = changeInterlocutor
        self.addText = addText
        self.addPhoto = addPhoto
        self.addSticker = addSticker
        self.addVoice = addVoice
        self.addFile = addFile
        self.openMessageActions = openMessageActions
        self.sendAll = sendAll
    }
}

private func pampGramVisualChatMenuController(context: AccountContext, peerId: EnginePeer.Id) -> ViewController {
    var presentTooltipImpl: ((String) -> Void)?
    var popImpl: (() -> Void)?

    let ordinalCounter = Atomic<Int>(value: 0)
    let draftsState = Atomic<[PampGramVisualChatDraft]>(value: [])
    let draftsPromise = ValuePromise<[PampGramVisualChatDraft]>([], ignoreRepeated: false)
    func mutateDrafts(_ f: (inout [PampGramVisualChatDraft]) -> Void) {
        let updated = draftsState.modify { current in
            var copy = current
            f(&copy)
            return copy
        }
        draftsPromise.set(updated)
    }

    let placeholderInterlocutor = PampGramVisualChatInterlocutor(id: peerId, displayName: "Собеседник")
    let interlocutorState = Atomic<PampGramVisualChatInterlocutor>(value: placeholderInterlocutor)
    let interlocutorPromise = ValuePromise<PampGramVisualChatInterlocutor>(placeholderInterlocutor, ignoreRepeated: false)
    func setInterlocutor(_ value: PampGramVisualChatInterlocutor) {
        let _ = interlocutorState.swap(value)
        interlocutorPromise.set(value)
    }

    // Seed the real display name of the chat's own peer as soon as it resolves — near-instant
    // in practice, since this is the peer of the chat that's already open.
    let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
    |> deliverOnMainQueue).startStandalone(next: { peer in
        guard let peer else {
            return
        }
        setInterlocutor(PampGramVisualChatInterlocutor(id: peer.id, displayName: peer.compactDisplayTitle))
    })

    let appendDraft: (Bool, PampGramVisualChatContent) -> Void = { isIncoming, content in
        let interlocutor = interlocutorState.with { $0 }
        let ordinal = ordinalCounter.modify { $0 + 1 }
        let draft = PampGramVisualChatDraft(
            ordinal: ordinal,
            isIncoming: isIncoming,
            authorId: isIncoming ? interlocutor.id : context.account.peerId,
            authorLabel: isIncoming ? interlocutor.displayName : "Я",
            content: content,
            reaction: nil
        )
        mutateDrafts { $0.append(draft) }
    }

    let presentRoleChoice: (@escaping (Bool) -> Void) -> Void = { onChosen in
        guard let topController = pampGramVisualChatTopController(context: context) else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let interlocutorName = interlocutorState.with { $0 }.displayName
        let sheet = ActionSheetController(presentationData: presentationData)
        sheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: "От кого сообщение?"),
                ActionSheetButtonItem(title: "Я", color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    onChosen(false)
                }),
                ActionSheetButtonItem(title: interlocutorName, color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    onChosen(true)
                })
            ]),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                })
            ])
        ])
        topController.present(sheet, in: .window(.root))
    }

    let arguments = PampGramVisualChatArguments(
        changeInterlocutor: {
            guard let topController = pampGramVisualChatTopController(context: context) else {
                return
            }
            topController.present(promptController(
                context: context,
                text: "Сменить собеседника",
                subtitle: "Юзернейм (без @) — все следующие сообщения «от собеседника» будут от его лица. Уже добавленные сообщения не изменятся.",
                value: "",
                placeholder: "username",
                characterLimit: 64,
                apply: { value in
                    guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                        return
                    }
                    if value.hasPrefix("@") {
                        value.removeFirst()
                    }
                    let _ = (context.engine.peers.resolvePeerByName(name: value, referrer: nil)
                    |> deliverOnMainQueue).start(next: { result in
                        guard case let .result(peer) = result, let peer else {
                            presentTooltipImpl?("Пользователь «\(value)» не найден.")
                            return
                        }
                        setInterlocutor(PampGramVisualChatInterlocutor(id: peer.id, displayName: peer.compactDisplayTitle))
                        presentTooltipImpl?("Собеседник изменён на \(peer.compactDisplayTitle).")
                    })
                }
            ), in: .window(.root))
        },
        addText: {
            presentRoleChoice { isIncoming in
                guard let topController = pampGramVisualChatTopController(context: context) else {
                    return
                }
                topController.present(promptController(
                    context: context,
                    text: isIncoming ? "Текст собеседника" : "Текст от меня",
                    subtitle: "Добавится в конец переписки",
                    value: "",
                    placeholder: "Введите текст...",
                    characterLimit: 4096,
                    apply: { value in
                        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                            return
                        }
                        appendDraft(isIncoming, .text(text))
                    }
                ), in: .window(.root))
            }
        },
        addPhoto: {
            guard #available(iOS 14.0, *) else {
                return
            }
            presentRoleChoice { isIncoming in
                pampGramVisualChatPresentImagePicker(context: context) { media in
                    appendDraft(isIncoming, .photo(media))
                }
            }
        },
        addSticker: {
            guard #available(iOS 14.0, *) else {
                return
            }
            presentRoleChoice { isIncoming in
                pampGramVisualChatPresentImagePicker(context: context) { media in
                    appendDraft(isIncoming, .sticker(media))
                }
            }
        },
        addVoice: {
            presentRoleChoice { isIncoming in
                guard let topController = pampGramVisualChatTopController(context: context) else {
                    return
                }
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let sheet = ActionSheetController(presentationData: presentationData)
                let addSilent: (Int) -> Void = { duration in
                    guard let media = pampGramVisualChatBuildSilentVoiceMedia(durationSeconds: duration) else {
                        presentTooltipImpl?("Не получилось создать голосовое.")
                        return
                    }
                    appendDraft(isIncoming, .voice(media, durationSeconds: duration))
                }
                sheet.setItemGroups([
                    ActionSheetItemGroup(items: [
                        ActionSheetTextItem(title: "Голосовое сообщение"),
                        ActionSheetButtonItem(title: "Тишина, 3 сек", color: .accent, action: { [weak sheet] in
                            sheet?.dismissAnimated()
                            addSilent(3)
                        }),
                        ActionSheetButtonItem(title: "Тишина, 5 сек", color: .accent, action: { [weak sheet] in
                            sheet?.dismissAnimated()
                            addSilent(5)
                        }),
                        ActionSheetButtonItem(title: "Тишина, 10 сек", color: .accent, action: { [weak sheet] in
                            sheet?.dismissAnimated()
                            addSilent(10)
                        }),
                        ActionSheetButtonItem(title: "Выбрать аудиофайл", color: .accent, action: { [weak sheet] in
                            sheet?.dismissAnimated()
                            guard #available(iOS 14.0, *) else {
                                return
                            }
                            pampGramVisualChatPresentFilePicker(context: context, asVoice: true) { media, _ in
                                var duration = 0
                                if let mediaFile = media as? TelegramMediaFile {
                                    for attribute in mediaFile.attributes {
                                        if case let .Audio(_, dur, _, _, _) = attribute {
                                            duration = dur
                                        }
                                    }
                                }
                                appendDraft(isIncoming, .voice(media, durationSeconds: duration))
                            }
                        })
                    ]),
                    ActionSheetItemGroup(items: [
                        ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                            sheet?.dismissAnimated()
                        })
                    ])
                ])
                topController.present(sheet, in: .window(.root))
            }
        },
        addFile: {
            guard #available(iOS 14.0, *) else {
                return
            }
            presentRoleChoice { isIncoming in
                pampGramVisualChatPresentFilePicker(context: context, asVoice: false) { media, fileName in
                    appendDraft(isIncoming, .file(media, fileName: fileName))
                }
            }
        },
        openMessageActions: { ordinal in
            guard let topController = pampGramVisualChatTopController(context: context) else {
                return
            }
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: presentationData)
            sheet.setItemGroups([
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: "Поставить реакцию", color: .accent, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        guard let reactionTopController = pampGramVisualChatTopController(context: context) else {
                            return
                        }
                        let reactionSheet = ActionSheetController(presentationData: presentationData)
                        var reactionButtons: [ActionSheetItem] = [ActionSheetTextItem(title: "Реакция на сообщение")]
                        for emoji in pampGramGetPopularEmojis() {
                            reactionButtons.append(ActionSheetButtonItem(title: emoji, color: .accent, action: { [weak reactionSheet] in
                                reactionSheet?.dismissAnimated()
                                mutateDrafts { drafts in
                                    guard let index = drafts.firstIndex(where: { $0.ordinal == ordinal }) else {
                                        return
                                    }
                                    drafts[index].reaction = emoji
                                }
                            }))
                        }
                        reactionSheet.setItemGroups([
                            ActionSheetItemGroup(items: reactionButtons),
                            ActionSheetItemGroup(items: [
                                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak reactionSheet] in
                                    reactionSheet?.dismissAnimated()
                                })
                            ])
                        ])
                        reactionTopController.present(reactionSheet, in: .window(.root))
                    }),
                    ActionSheetButtonItem(title: "Удалить", color: .destructive, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        mutateDrafts { drafts in
                            drafts.removeAll(where: { $0.ordinal == ordinal })
                        }
                    })
                ]),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            topController.present(sheet, in: .window(.root))
        },
        sendAll: {
            let allDrafts = draftsState.with { $0 }
            guard !allDrafts.isEmpty else {
                return
            }
            let baseTimestamp = Int32(Date().timeIntervalSince1970)
            for (index, draft) in allDrafts.enumerated() {
                let timestamp = baseTimestamp + Int32(index)
                let text: String
                let media: [Media]
                switch draft.content {
                case let .text(value):
                    text = value
                    media = []
                case let .photo(value):
                    text = ""
                    media = [value]
                case let .sticker(value):
                    text = ""
                    media = [value]
                case let .voice(value, _):
                    text = ""
                    media = [value]
                case let .file(value, _):
                    text = ""
                    media = [value]
                }
                let reaction = draft.reaction
                let insert = pampGramVisualChatInsertMessage(context: context, chatPeerId: peerId, authorId: draft.authorId, isIncoming: draft.isIncoming, timestamp: timestamp, text: text, media: media)
                let _ = (insert |> deliverOnMainQueue).start(next: { messageId in
                    if let messageId, let reaction {
                        pampGramToggleMessageReaction(context: context, messageId: messageId, emoji: reaction)
                    }
                })
            }
            mutateDrafts { $0.removeAll() }
            presentTooltipImpl?("Визуальная переписка отправлена в чат.")
            popImpl?()
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        interlocutorPromise.get(),
        draftsPromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, interlocutor, drafts -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Визуальный чат"),
            leftNavigationButton: ItemListNavigationButton(content: .text("Собеседник"), style: .regular, enabled: true, action: {
                arguments.changeInterlocutor()
            }),
            rightNavigationButton: ItemListNavigationButton(content: .text("Отправить"), style: .bold, enabled: !drafts.isEmpty, action: {
                arguments.sendAll()
            }),
            backNavigationButton: nil,
            animateChanges: true
        )

        var entries: [PampGramVisualChatEntry] = [
            .interlocutorInfo("СОБЕСЕДНИК: \(interlocutor.displayName.uppercased())"),
            .addHeader("ДОБАВИТЬ В ПЕРЕПИСКУ"),
            .addText("📝 Текст"),
            .addPhoto("📷 Фото"),
            .addSticker("🎨 Стикер"),
            .addVoice("🎙 Голосовое"),
            .addFile("📄 Файл"),
            .messagesHeader("ЧЕРНОВИК (\(drafts.count))")
        ]
        if drafts.isEmpty {
            entries.append(.messagesEmpty("Пока пусто — добавьте сообщение выше, потом нажмите «Отправить»."))
        } else {
            for draft in drafts {
                let title = "\(draft.authorLabel): \(draft.content.icon) \(draft.content.preview)"
                entries.append(.messageRow(ordinal: draft.ordinal, title: title, label: draft.reaction ?? ""))
            }
        }

        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentTooltipImpl = { [weak controller] text in
        guard let controller else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }
    popImpl = { [weak controller] in
        if let navigationController = controller?.navigationController as? NavigationController {
            let _ = navigationController.popViewController(animated: true)
        }
    }
    return controller
}

/// Entry point for the attachment (paperclip) button's long-press gesture — pushes onto the
/// app's own live navigation controller rather than presenting a disconnected one, see this
/// file's header comment for why that distinction is what actually fixes the black screen.
public func pampGramPresentVisualChatMenu(context: AccountContext, peerId: EnginePeer.Id) {
    guard let navigationController = context.sharedContext.mainWindow?.viewController as? NavigationController else {
        return
    }
    navigationController.pushViewController(pampGramVisualChatMenuController(context: context, peerId: peerId))
}
