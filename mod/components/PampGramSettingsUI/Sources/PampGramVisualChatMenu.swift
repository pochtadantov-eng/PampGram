import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext
import PampGramCore

private struct VisualChatMessage {
    let id: UUID
    let isIncoming: Bool
    let text: String?
    let media: [Media]?

    static func textMessage(isIncoming: Bool, text: String) -> VisualChatMessage {
        return VisualChatMessage(
            id: UUID(),
            isIncoming: isIncoming,
            text: text,
            media: nil
        )
    }

    static func mediaMessage(isIncoming: Bool, media: [Media]) -> VisualChatMessage {
        return VisualChatMessage(
            id: UUID(),
            isIncoming: isIncoming,
            text: nil,
            media: media
        )
    }
}

/// Menu for creating visual chats with multiple messages from different speakers
public class PampGramVisualChatMenuController: ViewController {
    private let context: AccountContext
    private let peerId: EnginePeer.Id
    private let messages = Atomic<[VisualChatMessage]>(value: [])
    private let presentationData: PresentationData

    init(context: AccountContext, peerId: EnginePeer.Id) {
        self.context = context
        self.peerId = peerId
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }

        super.init(navigationBarPresentationData: NavigationBarPresentationData(
            theme: NavigationBarTheme(rootControllerTheme: self.presentationData.theme),
            strings: NavigationBarStrings(back: self.presentationData.strings.Common_Back, close: self.presentationData.strings.Common_Close)
        ))
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func loadView() {
        super.loadView()
        self.view.backgroundColor = self.presentationData.theme.list.plainBackgroundColor
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Визуальный чат"

        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = false
        self.view.addSubview(scrollView)

        let contentView = UIView()
        scrollView.addSubview(contentView)

        // Configure layout constraints
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: self.view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        // Create action buttons
        let buttonStackView = UIStackView()
        buttonStackView.axis = .vertical
        buttonStackView.spacing = 12
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(buttonStackView)

        NSLayoutConstraint.activate([
            buttonStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            buttonStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            buttonStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            buttonStackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16)
        ])

        // Button: Add text from me
        let addMyTextButton = self.createButton(
            title: "📝 Мой текст",
            action: { [weak self] in
                self?.presentAddTextMenu(incoming: false)
            }
        )
        buttonStackView.addArrangedSubview(addMyTextButton)

        // Button: Add text from interlocutor
        let addTheirTextButton = self.createButton(
            title: "💬 Текст собеседника",
            action: { [weak self] in
                self?.presentAddTextMenu(incoming: true)
            }
        )
        buttonStackView.addArrangedSubview(addTheirTextButton)

        // Button: Add photo from me
        let addMyPhotoButton = self.createButton(
            title: "📸 Фото от меня",
            action: { [weak self] in
                self?.presentAddPhotoMenu(incoming: false)
            }
        )
        buttonStackView.addArrangedSubview(addMyPhotoButton)

        // Button: Add photo from interlocutor
        let addTheirPhotoButton = self.createButton(
            title: "📷 Фото собеседника",
            action: { [weak self] in
                self?.presentAddPhotoMenu(incoming: true)
            }
        )
        buttonStackView.addArrangedSubview(addTheirPhotoButton)

        // Button: Add voice from me
        let addMyVoiceButton = self.createButton(
            title: "🎙️ Голос от меня",
            action: { [weak self] in
                self?.presentAddVoiceMenu(incoming: false)
            }
        )
        buttonStackView.addArrangedSubview(addMyVoiceButton)

        // Button: Add voice from interlocutor
        let addTheirVoiceButton = self.createButton(
            title: "🎧 Голос собеседника",
            action: { [weak self] in
                self?.presentAddVoiceMenu(incoming: true)
            }
        )
        buttonStackView.addArrangedSubview(addTheirVoiceButton)

        // Button: Send all messages
        let sendButton = self.createSendButton(
            title: "✅ Отправить",
            action: { [weak self] in
                self?.sendAllMessages()
            }
        )
        buttonStackView.addArrangedSubview(sendButton)

        // Navigation buttons
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Отмена",
            style: .plain,
            target: self,
            action: #selector(self.cancelTapped)
        )
    }

    private func createButton(title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.backgroundColor = self.presentationData.theme.list.itemBlocksBackgroundColor
        button.setTitleColor(self.presentationData.theme.list.itemPrimaryTextColor, for: .normal)
        button.layer.cornerRadius = 10
        button.layer.masksToBounds = true
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        button.addTarget(self, action: #selector(self.buttonTapped(_:)), for: .touchUpInside)
        button.tag = Int(bitPattern: ObjectIdentifier(action as! AnyObject).hashValue)
        objc_setAssociatedObject(button, &actionKey, action, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        return button
    }

    private func createSendButton(title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        button.backgroundColor = self.presentationData.theme.list.itemCheckColors.fillColor
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.layer.masksToBounds = true
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        button.addTarget(self, action: #selector(self.buttonTapped(_:)), for: .touchUpInside)
        objc_setAssociatedObject(button, &actionKey, action, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        return button
    }

    @objc private func buttonTapped(_ sender: UIButton) {
        if let action = objc_getAssociatedObject(sender, &actionKey) as? () -> Void {
            action()
        }
    }

    @objc private func cancelTapped() {
        self.dismiss()
    }

    private func presentAddTextMenu(incoming: Bool) {
        let controller = pampGramVisualChatTextInputController(
            context: self.context,
            peerId: self.peerId,
            isIncoming: incoming,
            onTextAdded: { [weak self] text in
                let message = VisualChatMessage.textMessage(isIncoming: incoming, text: text)
                let _ = self?.messages.modify { $0.append(message) }
                self?.dismiss()
            }
        )
        self.present(controller, in: .window(.root))
    }

    private func presentAddPhotoMenu(incoming: Bool) {
        pampGramVisualChatPresentInsertPhoto(
            context: self.context,
            peerId: self.peerId,
            isIncoming: incoming,
            onPhotoAdded: { [weak self] media in
                let message = VisualChatMessage.mediaMessage(isIncoming: incoming, media: [media])
                let _ = self?.messages.modify { $0.append(message) }
            }
        )
    }

    private func presentAddVoiceMenu(incoming: Bool) {
        pampGramVisualChatPresentInsertFile(
            context: self.context,
            peerId: self.peerId,
            isIncoming: incoming,
            asVoice: true,
            onFileAdded: { [weak self] media in
                let message = VisualChatMessage.mediaMessage(isIncoming: incoming, media: [media])
                let _ = self?.messages.modify { $0.append(message) }
            }
        )
    }

    private func sendAllMessages() {
        let allMessages = self.messages.with { $0 }

        guard !allMessages.isEmpty else {
            let alertController = UIAlertController(
                title: "Пусто",
                message: "Добавьте хотя бы одно сообщение",
                preferredStyle: .alert
            )
            alertController.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alertController, animated: true)
            return
        }

        for message in allMessages {
            if message.isIncoming {
                let _ = pampGramInsertIncomingMessage(
                    context: self.context,
                    peerId: self.peerId,
                    text: message.text ?? "",
                    media: message.media ?? []
                ).start()
            } else {
                let _ = pampGramInsertOutgoingMessage(
                    context: self.context,
                    peerId: self.peerId,
                    text: message.text ?? "",
                    media: message.media ?? []
                ).start()
            }
        }

        // Show tooltip
        guard let controller = pampGramTopController(context: self.context) else {
            self.dismiss()
            return
        }
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(
            presentationData: presentationData,
            content: .info(title: nil, text: "Визуальный чат добавлен в сообщения", timeout: nil, customUndoText: nil),
            elevatedLayout: false,
            action: { _ in return false }
        ), in: .current)

        self.dismiss()
    }
}

private var actionKey: Void?

private func pampGramTopController(context: AccountContext) -> ViewController? {
    return (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController as? ViewController
}

private func pampGramVisualChatTextInputController(
    context: AccountContext,
    peerId: EnginePeer.Id,
    isIncoming: Bool,
    onTextAdded: @escaping (String) -> Void
) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    return promptController(
        context: context,
        text: isIncoming ? "Текст собеседника" : "Текст от меня",
        subtitle: "Добавится в визуальный чат",
        value: "",
        placeholder: "Введите текст...",
        characterLimit: 4096,
        apply: { value in
            guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return
            }
            onTextAdded(text)
        }
    )
}

// Forward declarations for existing functions from PampGramFakeContentInsert.swift
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

private func pampGramInsertOutgoingMessage(context: AccountContext, peerId: EnginePeer.Id, text: String, media: [Media]) -> Signal<EngineMessage.Id?, NoError> {
    return context.account.postbox.transaction { transaction -> EngineMessage.Id? in
        let globallyUniqueId = Int64.random(in: Int64.min ... Int64.max)
        let storeMessage = StoreMessage(
            id: .Partial(peerId, Namespaces.Message.Local),
            customStableId: nil,
            globallyUniqueId: globallyUniqueId,
            groupingKey: nil,
            threadId: nil,
            timestamp: Int32(Date().timeIntervalSince1970),
            flags: StoreMessageFlags(),
            tags: [],
            globalTags: [],
            localTags: [],
            forwardInfo: nil,
            authorId: context.account.peerId,
            text: text,
            attributes: [],
            media: media
        )
        let insertedIds = transaction.addMessages([storeMessage], location: .Random)
        return insertedIds[globallyUniqueId]
    }
}

// Visual chat photo insertion with callback
@available(iOS 14.0, *)
private var pampGramVisualChatActivePhotoPickerDelegate: PampGramVisualChatPhotoPickerDelegate?

@available(iOS 14.0, *)
private final class PampGramVisualChatPhotoPickerDelegate: NSObject, PHPickerViewControllerDelegate {
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
private func pampGramVisualChatPresentInsertPhoto(
    context: AccountContext,
    peerId: EnginePeer.Id,
    isIncoming: Bool,
    onPhotoAdded: @escaping (Media) -> Void
) {
    guard let presentingController = pampGramTopUIViewController(context: context) else {
        return
    }

    let delegate = PampGramVisualChatPhotoPickerDelegate()
    pampGramVisualChatActivePhotoPickerDelegate = delegate
    delegate.completion = { image in
        pampGramVisualChatActivePhotoPickerDelegate = nil
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

        onPhotoAdded(media)
    }

    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = 1
    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = delegate
    presentingController.present(picker, animated: true, completion: nil)
}

@available(iOS 14.0, *)
private func pampGramVisualChatPresentInsertFile(
    context: AccountContext,
    peerId: EnginePeer.Id,
    isIncoming: Bool,
    asVoice: Bool,
    onFileAdded: @escaping (Media) -> Void
) {
    guard let presentingController = pampGramTopUIViewController(context: context) else {
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

        onFileAdded(file)
    }

    let contentTypes: [UTType] = asVoice ? [.audio] : [.item]
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
    picker.delegate = delegate
    presentingController.present(picker, animated: true, completion: nil)
}

@available(iOS 14.0, *)
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
private func pampGramVisualChatMimeType(forExtension ext: String) -> String {
    if let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
        return mime
    }
    return "application/octet-stream"
}

private func pampGramVisualChatPersistFile(data: Data, suggestedExtension: String) -> String? {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("PampGram/FakeMedia", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let safeExtension = suggestedExtension.isEmpty ? "dat" : suggestedExtension
    let path = dir.appendingPathComponent("\(Int64.random(in: 1...Int64.max)).\(safeExtension)")
    do {
        try data.write(to: path, options: .atomic)
        return path.path
    } catch {
        return nil
    }
}

private func pampGramTopUIViewController(context: AccountContext) -> UIViewController? {
    return (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController
}

/// Public API to present the visual chat menu
public func pampGramPresentVisualChatMenu(context: AccountContext, peerId: EnginePeer.Id) {
    guard let topController = pampGramTopController(context: context) else {
        return
    }
    let menuController = PampGramVisualChatMenuController(context: context, peerId: peerId)
    let navigationController = NavigationController(rootViewController: menuController)
    topController.present(navigationController, in: .window(.root))
}
