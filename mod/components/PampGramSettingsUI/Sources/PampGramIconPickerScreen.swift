import Foundation
import UIKit
import Display
import TelegramPresentationData
import AccountContext
import AppBundle

/// One tile in the icon grid: a rounded preview card with the icon centered inside it, the
/// display name below the card, and — only on the currently applied icon — a colored ring
/// around the whole card plus a checkmark badge in its corner, so the current choice reads
/// at a glance instead of needing a text label like the old one-row-per-icon list did.
private final class PampGramIconCell: UICollectionViewCell {
    static let reuseIdentifier = "PampGramIconCell"

    private let cardView = UIView()
    private let imageView = UIImageView()
    private let nameLabel = UILabel()
    private let checkmarkBadge = UIView()
    private let checkmarkIcon = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.cardView.backgroundColor = UIColor(rgb: 0x1c1c24)
        self.cardView.layer.cornerRadius = 20.0
        if #available(iOS 13.0, *) {
            self.cardView.layer.cornerCurve = .continuous
        }
        self.cardView.layer.borderWidth = 2.0
        self.cardView.layer.borderColor = UIColor.clear.cgColor
        self.cardView.clipsToBounds = false
        self.contentView.addSubview(self.cardView)

        self.imageView.contentMode = .scaleAspectFit
        self.imageView.layer.cornerRadius = 14.0
        if #available(iOS 13.0, *) {
            self.imageView.layer.cornerCurve = .continuous
        }
        self.imageView.clipsToBounds = true
        self.cardView.addSubview(self.imageView)

        self.nameLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .medium)
        self.nameLabel.textColor = UIColor.white
        self.nameLabel.textAlignment = .center
        self.nameLabel.numberOfLines = 1
        self.nameLabel.adjustsFontSizeToFitWidth = true
        self.nameLabel.minimumScaleFactor = 0.8
        self.contentView.addSubview(self.nameLabel)

        self.checkmarkBadge.backgroundColor = UIColor(rgb: 0x8e44ec)
        self.checkmarkBadge.layer.cornerRadius = 12.0
        self.checkmarkBadge.layer.borderWidth = 2.0
        self.checkmarkBadge.layer.borderColor = UIColor(rgb: 0x0e0e14).cgColor
        self.checkmarkBadge.isHidden = true
        self.contentView.addSubview(self.checkmarkBadge)

        self.checkmarkIcon.image = UIImage(systemName: "checkmark")?.withRenderingMode(.alwaysTemplate)
        self.checkmarkIcon.tintColor = .white
        self.checkmarkIcon.contentMode = .scaleAspectFit
        self.checkmarkBadge.addSubview(self.checkmarkIcon)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(icon: PresentationAppIcon, displayName: String, isSelected: Bool) {
        self.imageView.image = UIImage(named: icon.imageName, in: getAppBundle(), compatibleWith: nil)
        self.nameLabel.text = displayName
        self.checkmarkBadge.isHidden = !isSelected
        self.cardView.layer.borderColor = isSelected ? UIColor(rgb: 0x8e44ec).cgColor : UIColor.clear.cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = self.contentView.bounds.width
        let cardHeight = width * 1.05
        self.cardView.frame = CGRect(x: 0.0, y: 0.0, width: width, height: cardHeight)

        let imageSide = width * 0.6
        self.imageView.frame = CGRect(x: (width - imageSide) / 2.0, y: (cardHeight - imageSide) / 2.0, width: imageSide, height: imageSide)

        self.nameLabel.frame = CGRect(x: 0.0, y: cardHeight + 10.0, width: width, height: 16.0)

        let badgeSize: CGFloat = 24.0
        self.checkmarkBadge.frame = CGRect(x: width - badgeSize + 6.0, y: -6.0, width: badgeSize, height: badgeSize)
        self.checkmarkIcon.frame = self.checkmarkBadge.bounds.insetBy(dx: 6.0, dy: 6.0)
    }
}

private final class PampGramIconPickerViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private let context: AccountContext
    private let icons: [PresentationAppIcon]
    private var currentIconName: String?
    private let onSelect: (PresentationAppIcon) -> Void

    private var collectionView: UICollectionView!

    init(context: AccountContext, icons: [PresentationAppIcon], currentIconName: String?, onSelect: @escaping (PresentationAppIcon) -> Void) {
        self.context = context
        self.icons = icons
        self.currentIconName = currentIconName
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
        self.title = "Иконка приложения"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = UIColor(rgb: 0x0e0e14)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(self.closePressed))

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 16.0
        layout.minimumLineSpacing = 28.0
        layout.sectionInset = UIEdgeInsets(top: 24.0, left: 20.0, bottom: 24.0, right: 20.0)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.register(PampGramIconCell.self, forCellWithReuseIdentifier: PampGramIconCell.reuseIdentifier)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.showsVerticalScrollIndicator = false
        collectionView.alwaysBounceVertical = true
        self.view.addSubview(collectionView)
        self.collectionView = collectionView
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.collectionView.frame = self.view.bounds
        self.collectionView.contentInset = UIEdgeInsets(top: 0.0, left: 0.0, bottom: self.view.safeAreaInsets.bottom, right: 0.0)
    }

    @objc private func closePressed() {
        self.dismiss(animated: true, completion: nil)
    }

    private func isSelected(_ icon: PresentationAppIcon) -> Bool {
        return icon.name == (self.currentIconName ?? self.icons.first(where: { $0.isDefault })?.name)
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.icons.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PampGramIconCell.reuseIdentifier, for: indexPath) as! PampGramIconCell
        let icon = self.icons[indexPath.item]
        cell.configure(icon: icon, displayName: pampGramIconDisplayName(icon), isSelected: self.isSelected(icon))
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let columns = 2
        let spacing: CGFloat = 16.0
        let sideInsets: CGFloat = 40.0
        let availableWidth = collectionView.bounds.width - sideInsets - spacing * CGFloat(columns - 1)
        let width = max(120.0, floor(availableWidth / CGFloat(columns)))
        let cardHeight = width * 1.05
        return CGSize(width: width, height: cardHeight + 26.0)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        let icon = self.icons[indexPath.item]
        if self.isSelected(icon) {
            return
        }

        let alert = UIAlertController(
            title: "Сменить иконку?",
            message: "«\(pampGramIconDisplayName(icon))» станет иконкой приложения на домашнем экране.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Сменить", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            // Wait for iOS's own result instead of assuming success — `setAlternateIconName`
            // can and does fail (icon name not declared in the built app's Info.plist, no
            // alternate-icons support on this build, etc.), and applying the UI change
            // regardless made a real failure look like nothing happened at all.
            self.context.sharedContext.applicationBindings.requestSetAlternateIconName(icon.isDefault ? nil : icon.name, { [weak self] success in
                guard let self else { return }
                DispatchQueue.main.async {
                    if success {
                        self.currentIconName = icon.name
                        self.onSelect(icon)
                        self.collectionView.reloadData()
                    } else {
                        let failureAlert = UIAlertController(
                            title: "Не получилось сменить иконку",
                            message: "iOS отказала в смене иконки на «\(pampGramIconDisplayName(icon))». Возможно, эта сборка не поддерживает смену иконок на этом устройстве.",
                            preferredStyle: .alert
                        )
                        failureAlert.addAction(UIAlertAction(title: "Понятно", style: .default, handler: nil))
                        self.present(failureAlert, animated: true, completion: nil)
                    }
                }
            })
        }))
        self.present(alert, animated: true, completion: nil)
    }
}

/// Presents the 9-icon grid modally over whatever's currently on screen — a proper grid with
/// full-size previews and a checkmark on the active one, replacing the old one-row-per-icon
/// list (nine near-identical disclosure rows with a tiny thumbnail each, which is exactly the
/// "looks terrible" the picker used to be). `onSelect` only has to update the host screen's own
/// summary row; applying the icon and confirming with the user both happen in here.
public func pampGramPresentIconPicker(context: AccountContext, icons: [PresentationAppIcon], currentIconName: String?, onSelect: @escaping (PresentationAppIcon) -> Void) {
    guard let presentingController = (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController else {
        return
    }
    let pickerController = PampGramIconPickerViewController(context: context, icons: icons, currentIconName: currentIconName, onSelect: onSelect)
    let navigationController = UINavigationController(rootViewController: pickerController)
    presentingController.present(navigationController, animated: true, completion: nil)
}
