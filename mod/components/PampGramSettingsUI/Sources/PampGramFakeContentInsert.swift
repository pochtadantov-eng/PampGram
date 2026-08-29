import Foundation
import UIKit
import AVFoundation
import Photos
import PhotosUI
import UniformTypeIdentifiers
import Display
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext
import UndoUI
import PampGramCore

/// Backs the "PampGram" → "Отправить фото/голосовое/файл"/"Показать звонок" entries next to
/// "Изменить текст" in a message's long-press menu (see the patch to
/// `ChatInterfaceStateContextMenus.swift`) — the rest of "Изменить визуально". Each inserts a
/// brand-new message into the chat, authored by the other side, using the exact same
/// `Namespaces.Message.Local` + `Incoming` pattern as every other PampGram local-only insert
/// (phantom gifts, "Подарок мне", resurrected deletions). No marker is added on purpose — the
/// user explicitly asked for these to be indistinguishable from a real message, the same call
/// already made for the text-edit half of this feature.
///
/// Picking media never touches Telegram's real send pipeline: a photo becomes a
/// `TelegramMediaImage` over a `LocalFileReferenceMediaResource` pointing at a copy this file
/// keeps in the app's own Application Support folder — Telegram's stock fetch machinery
/// (`fetchLocalFileResource`, `Fetch.swift`) already knows how to read that resource type
/// straight off disk, no upload, no CDN, no `account.network` involved at any point.

@available(iOS 14.0, *)
private var pampGramActivePhotoPickerDelegate: PampGramPhotoPickerDelegate?
private var pampGramActiveDocumentPickerDelegate: PampGramDocumentPickerDelegate?

private func pampGramTopUIViewController(context: AccountContext) -> UIViewController? {
    return (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController
}

private func pampGramTopController(context: AccountContext) -> ViewController? {
    return pampGramTopUIViewController(context: context) as? ViewController
}

private func pampGramPresentTooltip(context: AccountContext, text: String) {
    guard let controller = pampGramTopController(context: context) else {
        return
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    controller.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
}

private func pampGramInsertIncomingMessage(context: AccountContext, peerId: EnginePeer.Id, text: String, media: [Media]) -> Signal<EngineMessage.Id?, NoError> {
    return context.account.postbox.transaction { transaction -> EngineMessage.Id? in
        let globallyUniqueId = Int64.random(in: Int64.min ... Int64.max)
        let storeMessage = StoreMessage(
            id: .Partial(peerId, Namespaces.Message.Local),
            customStableId: nil,
            globallyUniqueId: globallyUniqueId,
            groupingKey: nil,
            threadId: nil,
            timestamp: Int32(Date().timeIntervalSince1970),
            flags: StoreMessageFlags.Incoming,
            tags: [],
            globalTags: [],
            localTags: [],
            forwardInfo: nil,
            authorId: peerId,
            text: text,
            attributes: [],
            media: media
        )
        let insertedIds = transaction.addMessages([storeMessage], location: .Random)
        return insertedIds[globallyUniqueId]
    }
}

private func pampGramFakeMediaDirectory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("PampGram/FakeMedia", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Copies `data` into a permanent file this device owns — never deleted by PampGram itself,
/// never a temporary awaiting-upload path (unlike `isUniquelyReferencedTemporaryFile: true`,
/// which Telegram's own cleanup would eventually reclaim). Returns the file's path, or nil if
/// the write failed (disk full, sandbox issue).
private func pampGramPersistFile(data: Data, suggestedExtension: String) -> String? {
    let dir = pampGramFakeMediaDirectory()
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
private func pampGramMimeType(forExtension ext: String) -> String {
    if let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
        return mime
    }
    return "application/octet-stream"
}

// MARK: - Photo

@available(iOS 14.0, *)
private final class PampGramPhotoPickerDelegate: NSObject, PHPickerViewControllerDelegate {
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

/// "Отправить фото": opens the system photo picker (no photo-library permission prompt —
/// `PHPickerViewController` runs out-of-process) and inserts whatever gets picked as a new
/// incoming photo message.
@available(iOS 14.0, *)
public func pampGramPresentInsertPhoto(context: AccountContext, peerId: EnginePeer.Id) {
    guard let presentingController = pampGramTopUIViewController(context: context) else {
        return
    }

    let delegate = PampGramPhotoPickerDelegate()
    pampGramActivePhotoPickerDelegate = delegate
    delegate.completion = { image in
        pampGramActivePhotoPickerDelegate = nil
        guard let image, let data = image.jpegData(compressionQuality: 0.9) else {
            return
        }
        guard let path = pampGramPersistFile(data: data, suggestedExtension: "jpg") else {
            pampGramPresentTooltip(context: context, text: "Не получилось сохранить фото.")
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

        let _ = pampGramInsertIncomingMessage(context: context, peerId: peerId, text: "", media: [media]).start()
        pampGramPresentTooltip(context: context, text: "Фото добавлено.")
    }

    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = 1
    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = delegate
    presentingController.present(picker, animated: true, completion: nil)
}

// MARK: - File / voice

private final class PampGramDocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    var completion: ((URL) -> Void)?

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first {
            self.completion?(url)
        }
    }
}

/// "Отправить файл" / "Отправить голосовое": both go through the system document picker (no
/// permission prompt either); the only difference is `asVoice`, which decides whether the
/// picked file gets the `.Audio(isVoice: true, …)` attribute that makes Telegram render it as
/// a round voice bubble instead of a generic document. Duration is read straight off the
/// audio track — `AVURLAsset.duration` is already how the rest of this app reads a local
/// file's duration (see `CreatePeerAvatarSetup.swift`), not something invented for this.
@available(iOS 14.0, *)
public func pampGramPresentInsertFile(context: AccountContext, peerId: EnginePeer.Id, asVoice: Bool) {
    guard let presentingController = pampGramTopUIViewController(context: context) else {
        return
    }

    let delegate = PampGramDocumentPickerDelegate()
    pampGramActiveDocumentPickerDelegate = delegate
    delegate.completion = { url in
        pampGramActiveDocumentPickerDelegate = nil
        pampGramHandlePickedDocument(context: context, peerId: peerId, url: url, asVoice: asVoice)
    }

    let contentTypes: [UTType] = asVoice ? [.audio] : [.item]
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
    picker.delegate = delegate
    presentingController.present(picker, animated: true, completion: nil)
}

@available(iOS 14.0, *)
private func pampGramHandlePickedDocument(context: AccountContext, peerId: EnginePeer.Id, url: URL, asVoice: Bool) {
    guard let data = try? Data(contentsOf: url) else {
        pampGramPresentTooltip(context: context, text: "Не удалось прочитать файл.")
        return
    }
    let originalName = url.lastPathComponent
    let ext = url.pathExtension
    guard let path = pampGramPersistFile(data: data, suggestedExtension: ext) else {
        pampGramPresentTooltip(context: context, text: "Не получилось сохранить файл.")
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
        mimeType: asVoice ? "audio/ogg" : pampGramMimeType(forExtension: ext),
        size: Int64(data.count),
        attributes: attributes,
        alternativeRepresentations: []
    )

    let _ = pampGramInsertIncomingMessage(context: context, peerId: peerId, text: "", media: [file]).start()
    pampGramPresentTooltip(context: context, text: asVoice ? "Голосовое добавлено." : "Файл добавлен.")
}

// MARK: - Call

/// "Показать звонок": no media to pick at all — a call is a plain `TelegramMediaAction`, same
/// shape as a gift or a pinned message, just with `authorId` set to the other side so it reads
/// as a call *they* started. Two short ActionSheets (type, then duration) instead of a text
/// field — nothing here needs precision typing.
public func pampGramPresentInsertCall(context: AccountContext, peerId: EnginePeer.Id) {
    guard let presentingController = pampGramTopController(context: context) else {
        return
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }

    let insertCall: (Bool, PhoneCallDiscardReason, Int32) -> Void = { isVideo, discardReason, duration in
        let action = TelegramMediaAction(action: .phoneCall(callId: Int64.random(in: Int64.min...Int64.max), discardReason: discardReason, duration: duration > 0 ? duration : nil, isVideo: isVideo))
        let _ = pampGramInsertIncomingMessage(context: context, peerId: peerId, text: "", media: [action]).start()
        pampGramPresentTooltip(context: context, text: "Звонок добавлен.")
    }

    let showDurationSheet: (Bool) -> Void = { isVideo in
        let durationSheet = ActionSheetController(presentationData: presentationData)
        durationSheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: "Сколько длился звонок?"),
                ActionSheetButtonItem(title: "Не ответил (пропущенный)", color: .accent, action: { [weak durationSheet] in
                    durationSheet?.dismissAnimated()
                    insertCall(isVideo, .missed, 0)
                }),
                ActionSheetButtonItem(title: "30 секунд", color: .accent, action: { [weak durationSheet] in
                    durationSheet?.dismissAnimated()
                    insertCall(isVideo, .hangup, 30)
                }),
                ActionSheetButtonItem(title: "1 минута", color: .accent, action: { [weak durationSheet] in
                    durationSheet?.dismissAnimated()
                    insertCall(isVideo, .hangup, 60)
                }),
                ActionSheetButtonItem(title: "5 минут", color: .accent, action: { [weak durationSheet] in
                    durationSheet?.dismissAnimated()
                    insertCall(isVideo, .hangup, 300)
                }),
                ActionSheetButtonItem(title: "15 минут", color: .accent, action: { [weak durationSheet] in
                    durationSheet?.dismissAnimated()
                    insertCall(isVideo, .hangup, 900)
                })
            ]),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak durationSheet] in
                    durationSheet?.dismissAnimated()
                })
            ])
        ])
        presentingController.present(durationSheet, in: .window(.root))
    }

    let typeSheet = ActionSheetController(presentationData: presentationData)
    typeSheet.setItemGroups([
        ActionSheetItemGroup(items: [
            ActionSheetTextItem(title: "Какой звонок?"),
            ActionSheetButtonItem(title: "Аудиозвонок", color: .accent, action: { [weak typeSheet] in
                typeSheet?.dismissAnimated()
                showDurationSheet(false)
            }),
            ActionSheetButtonItem(title: "Видеозвонок", color: .accent, action: { [weak typeSheet] in
                typeSheet?.dismissAnimated()
                showDurationSheet(true)
            })
        ]),
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak typeSheet] in
                typeSheet?.dismissAnimated()
            })
        ])
    ])
    presentingController.present(typeSheet, in: .window(.root))
}
