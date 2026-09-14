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
import Photos
import PhotosUI

/**
 PampGramChannelVisualPhoto - визуальные фото в каналах с ограничениями
 =====================================================================

 Позволяет отправлять визуальные фото в каналах, где запрещена загрузка медиа.
 Фото отображается только на этом устройстве и не нарушает правила канала.
 */

/// Метаданные о визуальном фото в канале
struct ChannelVisualPhoto {
    let id: UUID
    let channelId: EnginePeer.Id
    let imagePath: String
    let timestamp: Date
    let caption: String?
    let dimensions: CGSize
}

private let channelVisualPhotosKey = "PampGram.ChannelVisualPhotos"

private var channelVisualPhotosStore: [String: ChannelVisualPhoto] = {
    if let data = UserDefaults.standard.data(forKey: channelVisualPhotosKey),
       let decoded = try? JSONDecoder().decode([String: ChannelVisualPhoto].self, from: data) {
        return decoded
    }
    return [:]
}()

// MARK: - Photo Picker

@available(iOS 14.0, *)
private var pampGramChannelPhotoPickerDelegate: PampGramChannelPhotoPickerDelegate?

@available(iOS 14.0, *)
private final class PampGramChannelPhotoPickerDelegate: NSObject, PHPickerViewControllerDelegate {
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

// MARK: - Channel Visual Photo Controller

public class PampGramChannelVisualPhotoController: ViewController {
    private let context: AccountContext
    private let channelId: EnginePeer.Id
    private let presentationData: PresentationData

    init(context: AccountContext, channelId: EnginePeer.Id) {
        self.context = context
        self.channelId = channelId
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

        self.title = "Визуальное фото"

        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = true
        self.view.addSubview(scrollView)

        let contentView = UIView()
        scrollView.addSubview(contentView)

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

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16)
        ])

        // Info label
        let infoLabel = UILabel()
        infoLabel.text = "📸 Выберите фото для визуального добавления в канал\n\nФото будет видно только на этом устройстве и не нарушит ограничения канала."
        infoLabel.numberOfLines = 0
        infoLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        infoLabel.textColor = self.presentationData.theme.list.itemSecondaryTextColor
        infoLabel.textAlignment = .center
        stackView.addArrangedSubview(infoLabel)

        // Add photo button
        let addPhotoButton = self.createButton(
            title: "📷 Выбрать фото",
            action: { [weak self] in
                self?.presentPhotoPickerWithCaption()
            }
        )
        stackView.addArrangedSubview(addPhotoButton)

        // View saved photos button
        let viewPhotosButton = self.createButton(
            title: "📁 Просмотреть сохраненные",
            action: { [weak self] in
                self?.presentSavedPhotosController()
            }
        )
        stackView.addArrangedSubview(viewPhotosButton)

        // Add spacer
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        stackView.addArrangedSubview(spacer)

        // Navigation
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
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        button.backgroundColor = self.presentationData.theme.list.itemCheckColors.fillColor
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.layer.masksToBounds = true
        button.contentEdgeInsets = UIEdgeInsets(top: 14, left: 20, bottom: 14, right: 20)
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

    private func presentPhotoPickerWithCaption() {
        presentChannelPhotoPickerWithCaption(
            context: self.context,
            channelId: self.channelId,
            onPhotoAdded: { [weak self] in
                self?.showSuccessMessage()
            }
        )
    }

    private func presentSavedPhotosController() {
        let controller = pampGramChannelVisualPhotosViewController(
            context: self.context,
            channelId: self.channelId
        )
        if let navigationController = self.navigationController as? NavigationController {
            navigationController.pushViewController(controller, animated: true)
        } else {
            self.present(UINavigationController(rootViewController: controller), animated: true)
        }
    }

    private func showSuccessMessage() {
        guard let controller = pampGramTopController(context: self.context) else {
            return
        }
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(
            presentationData: presentationData,
            content: .info(title: nil, text: "Фото добавлено в канал (видно только на этом устройстве)", timeout: nil, customUndoText: nil),
            elevatedLayout: false,
            action: { _ in return false }
        ), in: .current)
    }
}

// MARK: - Photos List View Controller

private func pampGramChannelVisualPhotosViewController(
    context: AccountContext,
    channelId: EnginePeer.Id
) -> ViewController {
    let controller = PampGramChannelVisualPhotosListController(context: context, channelId: channelId)
    return controller
}

private class PampGramChannelVisualPhotosListController: ViewController {
    private let context: AccountContext
    private let channelId: EnginePeer.Id
    private let presentationData: PresentationData

    init(context: AccountContext, channelId: EnginePeer.Id) {
        self.context = context
        self.channelId = channelId
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }

        super.init(navigationBarPresentationData: NavigationBarPresentationData(
            theme: NavigationBarTheme(rootControllerTheme: self.presentationData.theme),
            strings: NavigationBarStrings(back: self.presentationData.strings.Common_Back, close: self.presentationData.strings.Common_Close)
        ))
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        super.loadView()
        self.view.backgroundColor = self.presentationData.theme.list.plainBackgroundColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Визуальные фото"

        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = true
        self.view.addSubview(scrollView)

        let contentView = UIView()
        scrollView.addSubview(contentView)

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

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16)
        ])

        let photos = pampGramGetChannelVisualPhotos(channelId: channelId)

        if photos.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = "📭 Нет сохраненных фото"
            emptyLabel.numberOfLines = 0
            emptyLabel.font = UIFont.systemFont(ofSize: 16, weight: .regular)
            emptyLabel.textColor = self.presentationData.theme.list.itemSecondaryTextColor
            emptyLabel.textAlignment = .center
            stackView.addArrangedSubview(emptyLabel)
        } else {
            for photo in photos {
                if let image = UIImage(contentsOfFile: photo.imagePath) {
                    let photoView = self.createPhotoView(image: image, photo: photo)
                    stackView.addArrangedSubview(photoView)
                }
            }
        }

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        stackView.addArrangedSubview(spacer)

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Назад",
            style: .plain,
            target: self,
            action: #selector(self.backTapped)
        )
    }

    private func createPhotoView(image: UIImage, photo: ChannelVisualPhoto) -> UIView {
        let container = UIView()

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)

        imageView.heightAnchor.constraint(equalToConstant: 200).isActive = true
        imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
        imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
        imageView.topAnchor.constraint(equalTo: container.topAnchor).isActive = true

        var lastView: UIView = imageView

        if let caption = photo.caption, !caption.isEmpty {
            let captionLabel = UILabel()
            captionLabel.text = caption
            captionLabel.numberOfLines = 0
            captionLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
            captionLabel.textColor = self.presentationData.theme.list.itemPrimaryTextColor
            captionLabel.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(captionLabel)

            captionLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
            captionLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
            captionLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8).isActive = true

            lastView = captionLabel
        }

        let dateLabel = UILabel()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        dateLabel.text = formatter.string(from: photo.timestamp)
        dateLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        dateLabel.textColor = self.presentationData.theme.list.itemSecondaryTextColor
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(dateLabel)

        dateLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
        dateLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
        dateLabel.topAnchor.constraint(equalTo: lastView.bottomAnchor, constant: 4).isActive = true
        dateLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor).isActive = true

        return container
    }

    @objc private func backTapped() {
        if let navigationController = self.navigationController as? NavigationController {
            let _ = navigationController.popViewController(animated: true)
        } else {
            self.dismiss()
        }
    }
}

// MARK: - Public API

@available(iOS 14.0, *)
private func presentChannelPhotoPickerWithCaption(
    context: AccountContext,
    channelId: EnginePeer.Id,
    onPhotoAdded: @escaping () -> Void
) {
    guard let presentingController = pampGramTopUIViewController(context: context) else {
        return
    }

    let delegate = PampGramChannelPhotoPickerDelegate()
    pampGramChannelPhotoPickerDelegate = delegate
    delegate.completion = { image in
        pampGramChannelPhotoPickerDelegate = nil
        guard let image, let data = image.jpegData(compressionQuality: 0.9) else {
            return
        }

        guard let path = pampGramChannelVisualPhotoPersistFile(data: data, suggestedExtension: "jpg") else {
            return
        }

        let pixelSize: CGSize
        if let cgImage = image.cgImage {
            pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        } else {
            pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        }

        // Show caption input
        presentCaptionInput(context: context) { caption in
            pampGramSaveChannelVisualPhoto(
                channelId: channelId,
                imagePath: path,
                caption: caption,
                dimensions: pixelSize
            )
            onPhotoAdded()
        }
    }

    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = 1
    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = delegate
    presentingController.present(picker, animated: true, completion: nil)
}

private func presentCaptionInput(
    context: AccountContext,
    onCaption: @escaping (String?) -> Void
) {
    guard let controller = pampGramTopController(context: context) else {
        onCaption(nil)
        return
    }

    controller.present(promptController(
        context: context,
        text: "Подпись к фото",
        subtitle: "Необязательно",
        value: "",
        placeholder: "Введите подпись...",
        characterLimit: 256,
        apply: { value in
            let caption = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            onCaption(caption?.isEmpty == false ? caption : nil)
        }
    ), in: .window(.root))
}

/// Сохраняет визуальное фото в канал
public func pampGramSaveChannelVisualPhoto(
    channelId: EnginePeer.Id,
    imagePath: String,
    caption: String? = nil,
    dimensions: CGSize
) {
    let photo = ChannelVisualPhoto(
        id: UUID(),
        channelId: channelId,
        imagePath: imagePath,
        timestamp: Date(),
        caption: caption,
        dimensions: dimensions
    )

    let key = "\(channelId.namespace)_\(channelId.id)_\(photo.id)"
    channelVisualPhotosStore[key] = photo

    if let encoded = try? JSONEncoder().encode(channelVisualPhotosStore) {
        UserDefaults.standard.set(encoded, forKey: channelVisualPhotosKey)
    }
}

/// Получает все визуальные фото для канала
public func pampGramGetChannelVisualPhotos(channelId: EnginePeer.Id) -> [ChannelVisualPhoto] {
    return channelVisualPhotosStore.values
        .filter { $0.channelId == channelId }
        .sorted { $0.timestamp > $1.timestamp }
}

/// Удаляет визуальное фото из канала
public func pampGramRemoveChannelVisualPhoto(channelId: EnginePeer.Id, photoId: UUID) {
    let key = "\(channelId.namespace)_\(channelId.id)_\(photoId)"
    channelVisualPhotosStore.removeValue(forKey: key)

    if let encoded = try? JSONEncoder().encode(channelVisualPhotosStore) {
        UserDefaults.standard.set(encoded, forKey: channelVisualPhotosKey)
    }
}

/// Показывает меню визуальных фото в канале
public func pampGramPresentChannelVisualPhotoMenu(context: AccountContext, channelId: EnginePeer.Id) {
    guard let topController = pampGramTopController(context: context) else {
        return
    }

    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let photoController = PampGramChannelVisualPhotoController(context: context, channelId: channelId)
    let navigationController = NavigationController(mode: .single, theme: NavigationControllerTheme(presentationTheme: presentationData.theme))
    navigationController.viewControllers = [photoController]
    topController.present(navigationController, animated: true, completion: nil)
}

// MARK: - Helper Functions

private var actionKey: Void?

private func pampGramTopController(context: AccountContext) -> ViewController? {
    return (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController as? ViewController
}

private func pampGramTopUIViewController(context: AccountContext) -> UIViewController? {
    return (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController
}

private func pampGramChannelVisualPhotoPersistFile(data: Data, suggestedExtension: String) -> String? {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("PampGram/ChannelVisualPhotos", isDirectory: true)
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

// Codable conformance
extension ChannelVisualPhoto: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case channelId
        case imagePath
        case timestamp
        case caption
        case dimensionsWidth
        case dimensionsHeight
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let idString = try container.decode(String.self, forKey: .id)
        id = UUID(uuidString: idString) ?? UUID()
        let channelIdValue = try container.decode(Int64.self, forKey: .channelId)
        channelId = EnginePeer.Id(channelIdValue)
        imagePath = try container.decode(String.self, forKey: .imagePath)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        caption = try container.decodeIfPresent(String.self, forKey: .caption)
        let width = try container.decode(CGFloat.self, forKey: .dimensionsWidth)
        let height = try container.decode(CGFloat.self, forKey: .dimensionsHeight)
        dimensions = CGSize(width: width, height: height)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString, forKey: .id)
        try container.encode(channelId.toInt64(), forKey: .channelId)
        try container.encode(imagePath, forKey: .imagePath)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(caption, forKey: .caption)
        try container.encode(dimensions.width, forKey: .dimensionsWidth)
        try container.encode(dimensions.height, forKey: .dimensionsHeight)
    }
}
