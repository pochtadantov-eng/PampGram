import Foundation
import UIKit
import Display

/// The fake CryptoBot's "История": the list of operations. Every time a balance is edited with the
/// hidden gesture an operation is written (a deposit when the amount went up, a withdrawal when it
/// went down), and the whole list is kept in the settings, so it is still there after the app or
/// the mini app is closed and opened again.

struct PampGramFakeCryptoBotOperation: Codable, Equatable {
    /// 0 — deposit, 1 — withdrawal.
    let kind: Int32
    let code: String
    /// Signed: plus for a deposit, minus for a withdrawal.
    let amount: Double
    /// What the operation was worth in dollars, unsigned.
    let usd: Double
    let date: Int32
    let id: Int64
}

private let pampGramFakeCryptoBotHistoryLimit = 300

func pampGramFakeCryptoBotParseOperations(_ raw: String) -> [PampGramFakeCryptoBotOperation] {
    guard !raw.isEmpty, let data = raw.data(using: .utf8), let operations = try? JSONDecoder().decode([PampGramFakeCryptoBotOperation].self, from: data) else {
        return []
    }
    return operations
}

private func pampGramFakeCryptoBotSerializeOperations(_ operations: [PampGramFakeCryptoBotOperation]) -> String {
    guard let data = try? JSONEncoder().encode(operations), let text = String(data: data, encoding: .utf8) else {
        return ""
    }
    return text
}

/// The history text with the operation for a balance that went from `old` to `new` added (or the
/// same text when nothing changed).
func pampGramFakeCryptoBotAppendingOperation(raw: String, code: String, old: Double, new: Double, price: Double) -> String {
    let delta = new - old
    if !delta.isFinite || delta == 0.0 {
        return raw
    }
    var operations = pampGramFakeCryptoBotParseOperations(raw)
    operations.append(PampGramFakeCryptoBotOperation(
        kind: delta > 0.0 ? 0 : 1,
        code: code,
        amount: delta,
        usd: abs(delta) * price,
        date: Int32(clamping: Int(Date().timeIntervalSince1970)),
        id: Int64.random(in: 1 ... Int64.max)
    ))
    if operations.count > pampGramFakeCryptoBotHistoryLimit {
        operations.removeFirst(operations.count - pampGramFakeCryptoBotHistoryLimit)
    }
    return pampGramFakeCryptoBotSerializeOperations(operations)
}

// MARK: - Pieces

private let pampGramFakeCryptoBotHistoryGray = UIColor(rgb: 0x959595)
private let pampGramFakeCryptoBotHistoryGreen = UIColor(rgb: 0x2e9f4f)

private let pampGramFakeCryptoBotShortMonths = ["янв.", "февр.", "март", "апр.", "мая", "июн.", "июл.", "авг.", "сент.", "окт.", "нояб.", "дек."]
private let pampGramFakeCryptoBotLongMonths = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]

private func pampGramFakeCryptoBotDateParts(_ timestamp: Int32) -> DateComponents {
    return Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
}

/// "17 окт. 03:09".
private func pampGramFakeCryptoBotShortDate(_ timestamp: Int32) -> String {
    let parts = pampGramFakeCryptoBotDateParts(timestamp)
    let month = max(1, min(12, parts.month ?? 1))
    let time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    return "\(parts.day ?? 1) \(pampGramFakeCryptoBotShortMonths[month - 1]) " + time
}

/// "Сегодня", "Вчера" or "15 октября" (with the year when it is not this one).
private func pampGramFakeCryptoBotDayTitle(_ timestamp: Int32) -> String {
    let calendar = Calendar.current
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
    if calendar.isDateInToday(date) {
        return "Сегодня"
    }
    if calendar.isDateInYesterday(date) {
        return "Вчера"
    }
    let parts = pampGramFakeCryptoBotDateParts(timestamp)
    let month = max(1, min(12, parts.month ?? 1))
    var title = "\(parts.day ?? 1) \(pampGramFakeCryptoBotLongMonths[month - 1])"
    if parts.year != calendar.component(.year, from: Date()) {
        title += " " + String(parts.year ?? 0)
    }
    return title
}

private final class PampGramFakeCryptoBotFilterPill: UIControl {
    private let titleLabel = UILabel()
    private let chevron = UIImageView()

    init(placeholder: String) {
        super.init(frame: .zero)
        self.layer.cornerRadius = 19.5
        self.layer.borderWidth = 1.0
        self.layer.borderColor = UIColor(rgb: 0x2d2d2d).cgColor
        self.titleLabel.font = PampGramFakeCryptoBotFonts.font(13.0, .regular)
        self.titleLabel.textColor = pampGramFakeCryptoBotHistoryGray
        self.titleLabel.text = placeholder
        self.titleLabel.isUserInteractionEnabled = false
        self.addSubview(self.titleLabel)
        self.chevron.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12.0, weight: .medium))
        self.chevron.tintColor = pampGramFakeCryptoBotHistoryGray
        self.chevron.contentMode = .center
        self.chevron.isUserInteractionEnabled = false
        self.addSubview(self.chevron)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setTitle(_ text: String, active: Bool) {
        self.titleLabel.text = text
        self.titleLabel.textColor = active ? .white : pampGramFakeCryptoBotHistoryGray
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width
        let height = self.bounds.height
        self.titleLabel.frame = CGRect(x: 12.0, y: floor((height - 20.0) / 2.0), width: max(0.0, width - 12.0 - 28.0), height: 20.0)
        self.chevron.frame = CGRect(x: width - 14.0 - 16.0, y: floor((height - 16.0) / 2.0), width: 16.0, height: 16.0)
    }

    override var isHighlighted: Bool {
        didSet {
            self.alpha = self.isHighlighted ? 0.6 : 1.0
        }
    }
}

private final class PampGramFakeCryptoBotOperationRowView: UIView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let dateLabel = UILabel()
    private let amountLabel = UILabel()
    private let usdLabel = UILabel()
    private let separator = UIView()

    init(operation: PampGramFakeCryptoBotOperation, showsSeparator: Bool) {
        super.init(frame: .zero)
        let isDeposit = operation.kind == 0
        self.iconView.image = PampGramFakeCryptoBotAssets.image(isDeposit ? "act_deposit" : "act_withdraw")
        self.iconView.contentMode = .scaleAspectFit
        self.addSubview(self.iconView)

        self.titleLabel.font = PampGramFakeCryptoBotFonts.font(15.0, .regular)
        self.titleLabel.textColor = .white
        self.titleLabel.text = isDeposit ? "Пополнение" : "Вывод"
        self.addSubview(self.titleLabel)

        self.dateLabel.font = PampGramFakeCryptoBotFonts.font(13.0, .regular)
        self.dateLabel.textColor = pampGramFakeCryptoBotHistoryGray
        self.dateLabel.text = pampGramFakeCryptoBotShortDate(operation.date)
        self.addSubview(self.dateLabel)

        self.amountLabel.font = PampGramFakeCryptoBotFonts.font(15.0, .regular)
        self.amountLabel.textAlignment = .right
        self.amountLabel.textColor = isDeposit ? pampGramFakeCryptoBotHistoryGreen : .white
        self.amountLabel.text = (isDeposit ? "+" : "-") + pampGramFakeCryptoBotFormat(abs(operation.amount), fractionDigits: 9) + " " + operation.code
        self.amountLabel.adjustsFontSizeToFitWidth = true
        self.amountLabel.minimumScaleFactor = 0.7
        self.addSubview(self.amountLabel)

        self.usdLabel.font = PampGramFakeCryptoBotFonts.font(13.0, .regular)
        self.usdLabel.textAlignment = .right
        self.usdLabel.textColor = pampGramFakeCryptoBotHistoryGray
        self.usdLabel.text = "$" + pampGramFakeCryptoBotFormatUSD(operation.usd)
        self.addSubview(self.usdLabel)

        self.separator.backgroundColor = UIColor(rgb: 0x292929)
        self.separator.isHidden = !showsSeparator
        self.addSubview(self.separator)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width
        let height = self.bounds.height
        let textX: CGFloat = 69.0
        self.iconView.frame = CGRect(x: 16.0, y: floor((height - 40.0) / 2.0), width: 40.0, height: 40.0)
        self.titleLabel.frame = CGRect(x: textX, y: floor(height / 2.0) - 20.0, width: 150.0, height: 20.0)
        self.dateLabel.frame = CGRect(x: textX, y: floor(height / 2.0) + 1.0, width: 150.0, height: 19.0)
        let rightWidth = max(0.0, width - 16.0 - 150.0 - 16.0)
        self.amountLabel.frame = CGRect(x: width - 16.0 - rightWidth, y: floor(height / 2.0) - 20.0, width: rightWidth, height: 20.0)
        self.usdLabel.frame = CGRect(x: width - 16.0 - rightWidth, y: floor(height / 2.0) + 1.0, width: rightWidth, height: 19.0)
        self.separator.frame = CGRect(x: textX, y: height - 1.0, width: max(0.0, width - textX - 16.0), height: 1.0)
    }
}

// MARK: - The page

final class PampGramFakeCryptoBotHistoryView: UIScrollView {
    /// 0 — type, 1 — coin, 2 — period.
    var onFilterPressed: ((Int) -> Void)?

    /// 0 — all, 1 — deposits, 2 — withdrawals.
    private(set) var typeFilter = 0
    private(set) var coinFilter: String?
    /// 0 — all time, 1 — today, 2 — 7 days, 3 — 30 days.
    private(set) var periodFilter = 0

    private var operations: [PampGramFakeCryptoBotOperation] = []
    private let pills: [PampGramFakeCryptoBotFilterPill] = [
        PampGramFakeCryptoBotFilterPill(placeholder: "Тип операции"),
        PampGramFakeCryptoBotFilterPill(placeholder: "Монета"),
        PampGramFakeCryptoBotFilterPill(placeholder: "Период")
    ]
    private var headers: [(label: UILabel, rows: [PampGramFakeCryptoBotOperationRowView])] = []
    private let emptyLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.showsVerticalScrollIndicator = false
        self.alwaysBounceVertical = true
        for (index, pill) in self.pills.enumerated() {
            pill.tag = index
            pill.addTarget(self, action: #selector(self.pillPressed(_:)), for: .touchUpInside)
            self.addSubview(pill)
        }
        self.emptyLabel.font = PampGramFakeCryptoBotFonts.font(15.0, .regular)
        self.emptyLabel.textColor = pampGramFakeCryptoBotHistoryGray
        self.emptyLabel.textAlignment = .center
        self.emptyLabel.text = "Нет операций"
        self.addSubview(self.emptyLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func pillPressed(_ sender: UIControl) {
        self.onFilterPressed?(sender.tag)
    }

    func setOperations(_ operations: [PampGramFakeCryptoBotOperation]) {
        if operations == self.operations {
            return
        }
        self.operations = operations
        self.rebuild()
    }

    func setTypeFilter(_ value: Int) {
        self.typeFilter = value
        self.pills[0].setTitle(value == 1 ? "Пополнение" : (value == 2 ? "Вывод" : "Тип операции"), active: value != 0)
        self.rebuild()
    }

    func setCoinFilter(_ value: String?) {
        self.coinFilter = value
        self.pills[1].setTitle(value ?? "Монета", active: value != nil)
        self.rebuild()
    }

    func setPeriodFilter(_ value: Int) {
        self.periodFilter = value
        let titles = ["Период", "Сегодня", "7 дней", "30 дней"]
        self.pills[2].setTitle(titles[max(0, min(3, value))], active: value != 0)
        self.rebuild()
    }

    private func filtered() -> [PampGramFakeCryptoBotOperation] {
        let now = Date()
        let calendar = Calendar.current
        var result: [PampGramFakeCryptoBotOperation] = []
        for operation in self.operations {
            if self.typeFilter == 1 && operation.kind != 0 {
                continue
            }
            if self.typeFilter == 2 && operation.kind != 1 {
                continue
            }
            if let coin = self.coinFilter, operation.code != coin {
                continue
            }
            let date = Date(timeIntervalSince1970: TimeInterval(operation.date))
            if self.periodFilter == 1 && !calendar.isDate(date, inSameDayAs: now) {
                continue
            }
            if self.periodFilter == 2 && now.timeIntervalSince(date) > 7.0 * 86400.0 {
                continue
            }
            if self.periodFilter == 3 && now.timeIntervalSince(date) > 30.0 * 86400.0 {
                continue
            }
            result.append(operation)
        }
        // Newest first.
        result.sort { $0.date > $1.date }
        return result
    }

    private func rebuild() {
        for header in self.headers {
            header.label.removeFromSuperview()
            for row in header.rows {
                row.removeFromSuperview()
            }
        }
        self.headers.removeAll()

        var currentTitle: String?
        var currentRows: [PampGramFakeCryptoBotOperation] = []
        var groups: [(String, [PampGramFakeCryptoBotOperation])] = []
        for operation in self.filtered() {
            let title = pampGramFakeCryptoBotDayTitle(operation.date)
            if title != currentTitle {
                if let currentTitle = currentTitle {
                    groups.append((currentTitle, currentRows))
                }
                currentTitle = title
                currentRows = []
            }
            currentRows.append(operation)
        }
        if let currentTitle = currentTitle {
            groups.append((currentTitle, currentRows))
        }

        for group in groups {
            let label = UILabel()
            label.font = PampGramFakeCryptoBotFonts.font(15.0, .regular)
            label.textColor = pampGramFakeCryptoBotHistoryGray
            label.text = group.0
            self.addSubview(label)
            var rows: [PampGramFakeCryptoBotOperationRowView] = []
            for (index, operation) in group.1.enumerated() {
                let row = PampGramFakeCryptoBotOperationRowView(operation: operation, showsSeparator: index < group.1.count - 1)
                self.addSubview(row)
                rows.append(row)
            }
            self.headers.append((label: label, rows: rows))
        }
        self.emptyLabel.isHidden = !groups.isEmpty
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width

        let pillWidths: [CGFloat] = [128.0, 104.5, 104.5]
        var pillX: CGFloat = 16.0
        for (index, pill) in self.pills.enumerated() {
            pill.frame = CGRect(x: pillX, y: 17.0, width: pillWidths[index], height: 39.0)
            pillX += pillWidths[index] + 12.5
        }

        // Section title 22 high; its rows start 23 below its middle; the next title's middle is 41.8
        // below the last row.
        var middle: CGFloat = 98.0
        for header in self.headers {
            header.label.frame = CGRect(x: 16.0, y: middle - 11.0, width: max(0.0, width - 32.0), height: 22.0)
            var y = middle + 23.0
            for row in header.rows {
                row.frame = CGRect(x: 0.0, y: y, width: width, height: 65.0)
                y += 65.0
            }
            middle = y + 41.8
        }
        self.emptyLabel.frame = CGRect(x: 16.0, y: 150.0, width: max(0.0, width - 32.0), height: 24.0)
        self.contentSize = CGSize(width: width, height: max(self.bounds.height + 1.0, middle + 60.0))
    }
}
