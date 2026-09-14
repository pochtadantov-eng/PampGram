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

/**
 PampGramChannelScreenCapture - захват экрана в каналах с блокировкой
 ====================================================================

 Позволяет делать скриншоты и сохранять их как визуальные фото,
 даже когда канал блокирует скриншоты (показывает черный экран).
 */

struct ChannelScreenCapture {
    let id: UUID
    let channelId: EnginePeer.Id
    let imagePath: String
    let timestamp: Date
    let screenHeight: CGFloat
    let screenWidth: CGFloat
}

private let channelScreenCapturesKey = "PampGram.ChannelScreenCaptures"

private var channelScreenCapturesStore: [String: ChannelScreenCapture] = {
    if let data = UserDefaults.standard.data(forKey: channelScreenCapturesKey),
       let decoded = try? JSONDecoder().decode([String: ChannelScreenCapture].self, from: data) {
        return decoded
    }
    return [:]
}()

// MARK: - Screen Capture Controller

public class PampGramChannelScreenCaptureController: ViewController {
    private let context: AccountContext
    private let channelId: EnginePeer.Id
    private let presentationData: PresentationData
    private var capturedImageView: UIImageView?

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

        self.title = "Захват экрана канала"

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
        infoLabel.text = "📸 Захват экрана канала\n\nОбойти блокировку скриншотов и сохранить изображение экрана как визуальное фото в канале."
        infoLabel.numberOfLines = 0
        infoLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        infoLabel.textColor = self.presentationData.theme.list.itemSecondaryTextColor
        infoLabel.textAlignment = .center
        stackView.addArrangedSubview(infoLabel)

        // Capture current screen button
        let captureButton = self.createButton(
            title: "📷 Захватить экран",
            subtitle: "Сохраняет текущий вид экрана",
            action: { [weak self] in
                self?.captureCurrentScreen()
            }
        )
        stackView.addArrangedSubview(captureButton)

        // View previous captures button
        let viewButton = self.createButton(
            title: "📁 Просмотреть захваты",
            subtitle: "История всех сохраненных скриншотов",
            action: { [weak self] in
                self?.presentCapturesViewController()
            }
        )
        stackView.addArrangedSubview(viewButton)

        // Quick capture button with large area
        let quickCaptureButton = self.createLargeButton(
            title: "⚡ БЫСТРЫЙ ЗАХВАТ",
            subtitle: "Нажмите и удерживайте для захвата",
            action: { [weak self] in
                self?.captureCurrentScreen()
            }
        )
        stackView.addArrangedSubview(quickCaptureButton)

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

    private func createButton(title: String, subtitle: String, action: @escaping () -> Void) -> UIView {
        let container = UIView()
        let button = UIButton(type: .system)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .white

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        subtitleLabel.numberOfLines = 0

        let stackView = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stackView.axis = .vertical
        stackView.spacing = 4
        stackView.alignment = .center

        button.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        button.backgroundColor = self.presentationData.theme.list.itemCheckColors.fillColor
        button.layer.cornerRadius = 12
        button.layer.masksToBounds = true
        button.contentEdgeInsets = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 80).isActive = true

        container.addSubview(button)

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            stackView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: button.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor, constant: -8)
        ])

        button.addTarget(self, action: #selector(self.buttonTapped(_:)), for: .touchUpInside)
        objc_setAssociatedObject(button, &actionKey, action, .OBJC_ASSOCIATION_COPY_NONATOMIC)

        return container
    }

    private func createLargeButton(title: String, subtitle: String, action: @escaping () -> Void) -> UIView {
        let container = UIView()
        let button = UIButton(type: .system)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .white

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        subtitleLabel.numberOfLines = 0

        let stackView = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stackView.axis = .vertical
        stackView.spacing = 6
        stackView.alignment = .center

        button.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        button.backgroundColor = UIColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1.0)
        button.layer.cornerRadius = 16
        button.layer.masksToBounds = true
        button.contentEdgeInsets = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 120).isActive = true

        container.addSubview(button)

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            stackView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: button.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor, constant: -12)
        ])

        button.addTarget(self, action: #selector(self.buttonTapped(_:)), for: .touchUpInside)
        objc_setAssociatedObject(button, &actionKey, action, .OBJC_ASSOCIATION_COPY_NONATOMIC)

        return container
    }

    @objc private func buttonTapped(_ sender: UIButton) {
        if let action = objc_getAssociatedObject(sender, &actionKey) as? () -> Void {
            action()
        }
    }

    @objc private func cancelTapped() {
        self.dismiss()
    }

    private func captureCurrentScreen() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else {
            return
        }

        let size = window.bounds.size
        UIGraphicsBeginImageContextWithOptions(size, true, 0.0)

        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return
        }

        // Рисуем весь контент окна
        window.layer.render(in: context)

        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            UIGraphicsEndImageContext()
            return
        }

        UIGraphicsEndImageContext()

        // Сохраняем захват
        saveScreenCapture(image: image)
    }

    private func saveScreenCapture(image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            showErrorMessage("Не удалось обработать изображение")
            return
        }

        guard let path = pampGramChannelScreenCapturePersistFile(data: data, suggestedExtension: "jpg") else {
            showErrorMessage("Не удалось сохранить скриншот")
            return
        }

        pampGramSaveChannelScreenCapture(
            channelId: self.channelId,
            imagePath: path,
            screenSize: image.size
        )

        showSuccessMessage()
    }

    private func presentCapturesViewController() {
        let controller = pampGramChannelCapturesViewController(
            context: self.context,
            channelId: self.channelId
        )
        if let navigationController = self.navigationController as? NavigationController {
            navigationController.pushViewController(controller, animated: true)
        }
    }

    private func showSuccessMessage() {
        guard let controller = pampGramTopController(context: self.context) else {
            return
        }
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(
            presentationData: presentationData,
            content: .info(title: nil, text: "✅ Скриншот сохранен!", timeout: nil, customUndoText: nil),
            elevatedLayout: false,
            action: { _ in return false }
        ), in: .current)
    }

    private func showErrorMessage(_ text: String) {
        guard let controller = pampGramTopController(context: self.context) else {
            return
        }
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(
            presentationData: presentationData,
            content: .info(title: nil, text: text, timeout: nil, customUndoText: nil),
            elevatedLayout: false,
            action: { _ in return false }
        ), in: .current)
    }
}

// MARK: - Captures List View Controller

private func pampGramChannelCapturesViewController(
    context: AccountContext,
    channelId: EnginePeer.Id
) -> ViewController {
    return PampGramChannelCapturesListController(context: context, channelId: channelId)
}

private class PampGramChannelCapturesListController: ViewController {
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

        self.title = "Сохраненные захваты"

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

        let captures = pampGramGetChannelScreenCaptures(channelId: channelId)

        if captures.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = "📭 Нет сохраненных захватов"
            emptyLabel.numberOfLines = 0
            emptyLabel.font = UIFont.systemFont(ofSize: 16, weight: .regular)
            emptyLabel.textColor = self.presentationData.theme.list.itemSecondaryTextColor
            emptyLabel.textAlignment = .center
            stackView.addArrangedSubview(emptyLabel)
        } else {
            for capture in captures {
                if let image = UIImage(contentsOfFile: capture.imagePath) {
                    let captureView = self.createCaptureView(image: image, capture: capture)
                    stackView.addArrangedSubview(captureView)
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

    private func createCaptureView(image: UIImage, capture: ChannelScreenCapture) -> UIView {
        let container = UIView()

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)

        imageView.heightAnchor.constraint(equalToConstant: 180).isActive = true
        imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
        imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
        imageView.topAnchor.constraint(equalTo: container.topAnchor).isActive = true

        let dateLabel = UILabel()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        dateLabel.text = formatter.string(from: capture.timestamp)
        dateLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        dateLabel.textColor = self.presentationData.theme.list.itemSecondaryTextColor
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(dateLabel)

        dateLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
        dateLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
        dateLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8).isActive = true
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

/// Сохраняет захват экрана канала
public func pampGramSaveChannelScreenCapture(
    channelId: EnginePeer.Id,
    imagePath: String,
    screenSize: CGSize
) {
    let capture = ChannelScreenCapture(
        id: UUID(),
        channelId: channelId,
        imagePath: imagePath,
        timestamp: Date(),
        screenHeight: screenSize.height,
        screenWidth: screenSize.width
    )

    let key = "\(channelId.namespace)_\(channelId.id)_\(capture.id)"
    channelScreenCapturesStore[key] = capture

    if let encoded = try? JSONEncoder().encode(channelScreenCapturesStore) {
        UserDefaults.standard.set(encoded, forKey: channelScreenCapturesKey)
    }
}

/// Получает все захваты для канала
public func pampGramGetChannelScreenCaptures(channelId: EnginePeer.Id) -> [ChannelScreenCapture] {
    return channelScreenCapturesStore.values
        .filter { $0.channelId == channelId }
        .sorted { $0.timestamp > $1.timestamp }
}

/// Удаляет захват
public func pampGramRemoveChannelScreenCapture(channelId: EnginePeer.Id, captureId: UUID) {
    let key = "\(channelId.namespace)_\(channelId.id)_\(captureId)"
    channelScreenCapturesStore.removeValue(forKey: key)

    if let encoded = try? JSONEncoder().encode(channelScreenCapturesStore) {
        UserDefaults.standard.set(encoded, forKey: channelScreenCapturesKey)
    }
}

/// Показывает меню захвата экрана
public func pampGramPresentChannelScreenCaptureMenu(context: AccountContext, channelId: EnginePeer.Id) {
    guard let topController = pampGramTopController(context: context) else {
        return
    }

    let captureController = PampGramChannelScreenCaptureController(context: context, channelId: channelId)
    let navigationController = NavigationController(rootViewController: captureController)
    topController.present(navigationController, in: .window(.root))
}

// MARK: - Helper Functions

private var actionKey: Void?

private func pampGramTopController(context: AccountContext) -> ViewController? {
    return (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController as? ViewController
}

private func pampGramChannelScreenCapturePersistFile(data: Data, suggestedExtension: String) -> String? {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("PampGram/ScreenCaptures", isDirectory: true)
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
extension ChannelScreenCapture: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case channelId
        case imagePath
        case timestamp
        case screenHeight
        case screenWidth
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let idString = try container.decode(String.self, forKey: .id)
        id = UUID(uuidString: idString) ?? UUID()
        let channelIdValue = try container.decode(Int64.self, forKey: .channelId)
        channelId = EnginePeer.Id(channelIdValue)
        imagePath = try container.decode(String.self, forKey: .imagePath)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        screenHeight = try container.decode(CGFloat.self, forKey: .screenHeight)
        screenWidth = try container.decode(CGFloat.self, forKey: .screenWidth)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString, forKey: .id)
        try container.encode(channelId.toInt64(), forKey: .channelId)
        try container.encode(imagePath, forKey: .imagePath)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(screenHeight, forKey: .screenHeight)
        try container.encode(screenWidth, forKey: .screenWidth)
    }
}
