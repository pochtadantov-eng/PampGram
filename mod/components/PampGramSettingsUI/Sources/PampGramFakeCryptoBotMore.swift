import Foundation
import UIKit
import Display

/// The fake CryptoBot's last tab, "Ещё": the sections "Кошелёк", "Торговля" and "Аккаунт" as grids
/// of tiles, "Помощь" and "Документы" as lists. The tiles are cut from a screenshot of the real
/// page. The tiles that lead to the screens that exist here open them; the others say that the
/// function is not available.

private struct PGMoreItem {
    let id: String
    let title: String
    let asset: String
}

private struct PGMoreSection {
    let title: String
    let glyph: String
    let items: [PGMoreItem]
}

private let pgMoreSections: [PGMoreSection] = [
    PGMoreSection(title: "Кошелёк", glyph: "s_wallet", items: [
        PGMoreItem(id: "deposit", title: "Пополнить", asset: "m_deposit"),
        PGMoreItem(id: "withdraw", title: "Вывести", asset: "m_withdraw"),
        PGMoreItem(id: "qrpay", title: "QR Pay", asset: "m_qrpay"),
        PGMoreItem(id: "history", title: "История", asset: "m_history"),
        PGMoreItem(id: "pay", title: "Crypto Pay", asset: "m_pay"),
        PGMoreItem(id: "book", title: "Книга адресов", asset: "m_book"),
        PGMoreItem(id: "fees", title: "Комиссии", asset: "m_fees")
    ]),
    PGMoreSection(title: "Торговля", glyph: "s_trade", items: [
        PGMoreItem(id: "swap", title: "Обмен", asset: "m_swap"),
        PGMoreItem(id: "exchange", title: "Биржа", asset: "m_exchange"),
        PGMoreItem(id: "p2p", title: "P2P Маркет", asset: "m_p2p"),
        PGMoreItem(id: "p2c", title: "P2C", asset: "m_p2c")
    ]),
    PGMoreSection(title: "Аккаунт", glyph: "s_account", items: [
        PGMoreItem(id: "settings", title: "Настройки", asset: "m_settings"),
        PGMoreItem(id: "security", title: "Безопасность", asset: "m_security"),
        PGMoreItem(id: "verify", title: "Верификация", asset: "m_verify"),
        PGMoreItem(id: "notify", title: "Уведомления", asset: "m_notify"),
        PGMoreItem(id: "wallpaper", title: "Обои", asset: "m_wallpaper"),
        PGMoreItem(id: "vouchers", title: "Ваучеры", asset: "m_vouchers")
    ])
]

private let pgMoreHelp: [PGMoreItem] = [
    PGMoreItem(id: "help", title: "Справка Crypto Bot", asset: "h_info"),
    PGMoreItem(id: "support", title: "Написать в поддержку", asset: "h_support"),
    PGMoreItem(id: "feedback", title: "Обратная связь", asset: "h_mail")
]

private let pgMoreDocs: [PGMoreItem] = [
    PGMoreItem(id: "privacy", title: "Политика конфиденциальности", asset: "h_privacy"),
    PGMoreItem(id: "aml", title: "Политика AML", asset: "h_aml")
]

private final class PGMoreTile: UIControl {
    let itemId: String
    private let imageView = UIImageView()
    private let label = UILabel()

    init(item: PGMoreItem) {
        self.itemId = item.id
        super.init(frame: .zero)
        self.imageView.image = PampGramFakeCryptoBotAssets.image(item.asset)
        self.imageView.contentMode = .scaleAspectFit
        self.imageView.isUserInteractionEnabled = false
        self.addSubview(self.imageView)
        self.label.text = item.title
        self.label.font = PampGramFakeCryptoBotFonts.font(10.0, .medium)
        self.label.textColor = PampGramFakeCryptoBotColors.text
        self.label.textAlignment = .center
        self.label.isUserInteractionEnabled = false
        self.addSubview(self.label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width
        self.imageView.frame = CGRect(x: floor((width - 62.0) / 2.0), y: 0.0, width: 62.0, height: 62.0)
        self.label.frame = CGRect(x: 0.0, y: 70.0, width: width, height: 16.0)
    }

    override var isHighlighted: Bool {
        didSet {
            self.alpha = self.isHighlighted ? 0.6 : 1.0
        }
    }
}

private final class PGMoreListRow: UIControl {
    let itemId: String
    private let iconView = UIImageView()
    private let label = UILabel()
    private let arrow = UIImageView()
    private let separator = UIView()

    init(item: PGMoreItem, showsSeparator: Bool) {
        self.itemId = item.id
        super.init(frame: .zero)
        self.iconView.image = PampGramFakeCryptoBotAssets.image(item.asset)
        self.iconView.contentMode = .scaleAspectFit
        self.iconView.isUserInteractionEnabled = false
        self.addSubview(self.iconView)
        self.label.text = item.title
        self.label.font = PampGramFakeCryptoBotFonts.font(15.0, .regular)
        self.label.textColor = PampGramFakeCryptoBotColors.text
        self.label.isUserInteractionEnabled = false
        self.addSubview(self.label)
        self.arrow.image = PampGramFakeCryptoBotAssets.image("i_arrow")?.withRenderingMode(.alwaysTemplate)
        self.arrow.tintColor = PampGramFakeCryptoBotColors.secondary
        self.arrow.contentMode = .scaleAspectFit
        self.arrow.isUserInteractionEnabled = false
        self.addSubview(self.arrow)
        self.separator.backgroundColor = PampGramFakeCryptoBotColors.border
        self.separator.isHidden = !showsSeparator
        self.separator.isUserInteractionEnabled = false
        self.addSubview(self.separator)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width
        let height = self.bounds.height
        self.iconView.frame = CGRect(x: 24.0, y: floor((height - 28.0) / 2.0), width: 28.0, height: 28.0)
        self.label.frame = CGRect(x: 64.3, y: 0.0, width: max(0.0, width - 64.3 - 50.0), height: height)
        self.arrow.frame = CGRect(x: width - 40.7, y: floor((height - 13.3) / 2.0), width: 13.3, height: 13.3)
        self.separator.frame = CGRect(x: 64.0, y: height - 1.0, width: max(0.0, width - 64.0 - 24.0), height: 1.0)
    }

    override var isHighlighted: Bool {
        didSet {
            self.alpha = self.isHighlighted ? 0.6 : 1.0
        }
    }
}

final class PampGramFakeCryptoBotMoreView: UIScrollView {
    /// The id of the tile that was pressed ("deposit", "swap", "help", …).
    var onAction: ((String) -> Void)?

    private var headerGlyphs: [UIImageView] = []
    private var headerTitles: [UILabel] = []
    private var tiles: [[PGMoreTile]] = []
    private var helpHeader: (UIImageView, UILabel) = (UIImageView(), UILabel())
    private var docsHeader: (UIImageView, UILabel) = (UIImageView(), UILabel())
    private var helpRows: [PGMoreListRow] = []
    private var docsRows: [PGMoreListRow] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.showsVerticalScrollIndicator = false
        self.alwaysBounceVertical = true
        for section in pgMoreSections {
            let glyph = UIImageView()
            let title = UILabel()
            self.configureHeader(glyph, title, glyphName: section.glyph, text: section.title)
            self.headerGlyphs.append(glyph)
            self.headerTitles.append(title)
            var row: [PGMoreTile] = []
            for item in section.items {
                let tile = PGMoreTile(item: item)
                tile.addTarget(self, action: #selector(self.tilePressed(_:)), for: .touchUpInside)
                self.addSubview(tile)
                row.append(tile)
            }
            self.tiles.append(row)
        }
        self.configureHeader(self.helpHeader.0, self.helpHeader.1, glyphName: "s_help", text: "Помощь")
        self.configureHeader(self.docsHeader.0, self.docsHeader.1, glyphName: "s_docs", text: "Документы")
        for (index, item) in pgMoreHelp.enumerated() {
            let row = PGMoreListRow(item: item, showsSeparator: index + 1 < pgMoreHelp.count)
            row.addTarget(self, action: #selector(self.rowPressed(_:)), for: .touchUpInside)
            self.addSubview(row)
            self.helpRows.append(row)
        }
        for (index, item) in pgMoreDocs.enumerated() {
            let row = PGMoreListRow(item: item, showsSeparator: index + 1 < pgMoreDocs.count)
            row.addTarget(self, action: #selector(self.rowPressed(_:)), for: .touchUpInside)
            self.addSubview(row)
            self.docsRows.append(row)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureHeader(_ glyph: UIImageView, _ title: UILabel, glyphName: String, text: String) {
        glyph.image = PampGramFakeCryptoBotAssets.image(glyphName)?.withRenderingMode(.alwaysTemplate)
        glyph.tintColor = PampGramFakeCryptoBotColors.secondary
        glyph.contentMode = .scaleAspectFit
        glyph.isUserInteractionEnabled = false
        self.addSubview(glyph)
        title.text = text
        title.font = PampGramFakeCryptoBotFonts.font(15.0, .medium)
        title.textColor = PampGramFakeCryptoBotColors.secondary
        title.isUserInteractionEnabled = false
        self.addSubview(title)
    }

    @objc private func tilePressed(_ sender: PGMoreTile) {
        self.onAction?(sender.itemId)
    }

    @objc private func rowPressed(_ sender: PGMoreListRow) {
        self.onAction?(sender.itemId)
    }

    private func placeHeader(_ glyph: UIImageView, _ title: UILabel, centerY: CGFloat) {
        let size = glyph.image?.size ?? CGSize(width: 14.0, height: 14.0)
        glyph.frame = CGRect(x: 24.7, y: centerY - size.height / 2.0, width: size.width, height: size.height)
        title.frame = CGRect(x: 48.7, y: centerY - 11.0, width: 250.0, height: 22.0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width
        // Four columns: the centres of the first and the last tile are 56 from the edges (96.7 apart on 402).
        let pitch = (width - 112.0) / 3.0
        let tileWidth: CGFloat = 90.0
        var centerY: CGFloat = 35.3
        var rowTop: CGFloat = 70.3
        for (sectionIndex, row) in self.tiles.enumerated() {
            self.placeHeader(self.headerGlyphs[sectionIndex], self.headerTitles[sectionIndex], centerY: centerY)
            rowTop = centerY + 34.7
            for (index, tile) in row.enumerated() {
                let column = index % 4
                let line = index / 4
                let centerX = 56.0 + CGFloat(column) * pitch
                tile.frame = CGRect(x: centerX - tileWidth / 2.0, y: rowTop + CGFloat(line) * 110.0, width: tileWidth, height: 90.0)
            }
            let lines = (row.count + 3) / 4
            // The last label sits 77 under its tile's top; the next header is 44.4 under that.
            centerY = rowTop + CGFloat(lines - 1) * 110.0 + 77.0 + 44.4
        }
        self.placeHeader(self.helpHeader.0, self.helpHeader.1, centerY: centerY)
        var rowCenter = centerY + 49.0
        for row in self.helpRows {
            row.frame = CGRect(x: 0.0, y: rowCenter - 26.0, width: width, height: 52.0)
            rowCenter += 52.0
        }
        centerY = rowCenter - 52.0 + 50.0
        self.placeHeader(self.docsHeader.0, self.docsHeader.1, centerY: centerY)
        rowCenter = centerY + 47.7
        for row in self.docsRows {
            row.frame = CGRect(x: 0.0, y: rowCenter - 26.0, width: width, height: 52.0)
            rowCenter += 52.0
        }
        self.contentSize = CGSize(width: width, height: rowCenter + 130.0)
    }
}
