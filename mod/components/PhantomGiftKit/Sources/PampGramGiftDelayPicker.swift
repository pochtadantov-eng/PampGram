import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData

/// "1 д 2 ч 3 мин 4 с" — only the non-zero parts (or "0 с").
public func pampGramDurationDescription(seconds: Int32) -> String {
    return pampGramDurationText(seconds: seconds, withDays: true)
}

/// Human wording for a delay picked with the wheels: "через 1 ч 5 мин 30 с".
public func pampGramGiftDelayDescription(seconds: Int32) -> String {
    return "через " + pampGramDurationText(seconds: seconds, withDays: false)
}

private func pampGramDurationText(seconds: Int32, withDays: Bool) -> String {
    var total = max(0, Int(seconds))
    var parts: [String] = []
    if withDays {
        let days = total / 86400
        total -= days * 86400
        if days != 0 {
            parts.append("\(days) д")
        }
    }
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours != 0 {
        parts.append("\(hours) ч")
    }
    if minutes != 0 {
        parts.append("\(minutes) мин")
    }
    if secs != 0 || parts.isEmpty {
        parts.append("\(secs) с")
    }
    return parts.joined(separator: " ")
}

private struct PampGramWheelUnit {
    let name: String
    let count: Int
    let seconds: Int
}

/// The wheels of the system Clock timer (hours / minutes / seconds, plus days for the cooldown). The
/// unit label is shown next to the number only on the row that is currently selected, like in the
/// Clock app.
private final class PampGramDelayWheel: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
    let units: [PampGramWheelUnit]
    private let textColor: UIColor
    var selected: [Int]

    init(units: [PampGramWheelUnit], initialSeconds: Int, textColor: UIColor) {
        self.units = units
        self.textColor = textColor
        var remaining = max(0, initialSeconds)
        var selected: [Int] = []
        for unit in units {
            let value = min(unit.count - 1, remaining / unit.seconds)
            selected.append(value)
            remaining -= value * unit.seconds
        }
        self.selected = selected
        super.init()
    }

    var totalSeconds: Int32 {
        var total = 0
        for (index, unit) in self.units.enumerated() {
            total += self.selected[index] * unit.seconds
        }
        return Int32(clamping: total)
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return self.units.count
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return self.units[component].count
    }

    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
        return 40.0
    }

    func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
        let width = pickerView.bounds.width / CGFloat(self.units.count)
        let container = (view as? PampGramDelayWheelRow) ?? PampGramDelayWheelRow(frame: CGRect(x: 0.0, y: 0.0, width: width, height: 40.0))
        container.frame = CGRect(x: 0.0, y: 0.0, width: width, height: 40.0)
        let isSelected = self.selected[component] == row
        container.update(number: "\(row)", unit: isSelected ? self.units[component].name : nil, textColor: self.textColor)
        return container
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        self.selected[component] = row
        pickerView.reloadComponent(component)
        pickerView.selectRow(row, inComponent: component, animated: false)
    }
}

private final class PampGramDelayWheelRow: UIView {
    private let numberLabel = UILabel()
    private let unitLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.numberLabel.textAlignment = .right
        self.numberLabel.font = UIFont.systemFont(ofSize: 24.0, weight: .regular)
        self.unitLabel.textAlignment = .left
        self.unitLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        self.addSubview(self.numberLabel)
        self.addSubview(self.unitLabel)
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    func update(number: String, unit: String?, textColor: UIColor) {
        self.numberLabel.text = number
        self.numberLabel.textColor = textColor
        self.unitLabel.text = unit
        self.unitLabel.textColor = textColor
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let split = floor(self.bounds.width * 0.5)
        self.numberLabel.frame = CGRect(x: 0.0, y: 0.0, width: split - 4.0, height: self.bounds.height)
        self.unitLabel.frame = CGRect(x: split + 4.0, y: 0.0, width: self.bounds.width - split - 4.0, height: self.bounds.height)
    }
}

private final class PampGramDelayPickerItem: ActionSheetItem {
    fileprivate let wheel: PampGramDelayWheel

    init(wheel: PampGramDelayWheel) {
        self.wheel = wheel
    }

    func node(theme: ActionSheetControllerTheme) -> ActionSheetItemNode {
        return PampGramDelayPickerItemNode(theme: theme, wheel: self.wheel)
    }

    func updateNode(_ node: ActionSheetItemNode) {
    }
}

private final class PampGramDelayPickerItemNode: ActionSheetItemNode {
    private let wheel: PampGramDelayWheel
    private let pickerNode: ASDisplayNode

    init(theme: ActionSheetControllerTheme, wheel: PampGramDelayWheel) {
        self.wheel = wheel
        self.pickerNode = ASDisplayNode(viewBlock: {
            let picker = UIPickerView()
            return picker
        })
        super.init(theme: theme)
        self.addSubnode(self.pickerNode)
    }

    override func didLoad() {
        super.didLoad()
        if let picker = self.pickerNode.view as? UIPickerView {
            picker.dataSource = self.wheel
            picker.delegate = self.wheel
            for component in 0 ..< self.wheel.units.count {
                picker.selectRow(self.wheel.selected[component], inComponent: component, animated: false)
            }
        }
    }

    override func updateLayout(constrainedSize: CGSize, transition: ContainedViewLayoutTransition) -> CGSize {
        let size = CGSize(width: constrainedSize.width, height: 200.0)
        self.updateInternalLayout(size, constrainedSize: constrainedSize)
        self.pickerNode.frame = CGRect(origin: CGPoint(), size: size)
        return size
    }
}

/// "Когда доставить подарок?": a timer-style wheel (hours, minutes, seconds) plus "Сразу".
/// `completion` gets the delay in seconds, or `nil` for "deliver right away".
public func pampGramPresentGiftDelaySheet(presentationData: PresentationData, present: (ViewController) -> Void, completion: @escaping (Int32?) -> Void) {
    let sheet = ActionSheetController(presentationData: presentationData)
    let wheel = PampGramDelayWheel(
        units: [
            PampGramWheelUnit(name: "ч", count: 100, seconds: 3600),
            PampGramWheelUnit(name: "мин", count: 60, seconds: 60),
            PampGramWheelUnit(name: "с", count: 60, seconds: 1)
        ],
        initialSeconds: 5 * 60,
        textColor: presentationData.theme.actionSheet.primaryTextColor
    )
    sheet.setItemGroups([
        ActionSheetItemGroup(items: [
            ActionSheetTextItem(title: "Когда доставить подарок?"),
            PampGramDelayPickerItem(wheel: wheel),
            ActionSheetButtonItem(title: "Запланировать", color: .accent, font: .bold, action: { [weak sheet] in
                let seconds = wheel.totalSeconds
                if seconds <= 0 {
                    return
                }
                sheet?.dismissAnimated()
                completion(seconds)
            }),
            ActionSheetButtonItem(title: "Сразу", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                completion(nil)
            })
        ]),
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                sheet?.dismissAnimated()
            })
        ])
    ])
    present(sheet)
}

/// The fake transfer cooldown: the same timer wheel with a days column in front. `completion` gets the
/// chosen length in seconds when "Запустить КД" is tapped (never 0).
public func pampGramPresentCooldownSheet(presentationData: PresentationData, initialSeconds: Int32, present: (ViewController) -> Void, completion: @escaping (Int32) -> Void) {
    let sheet = ActionSheetController(presentationData: presentationData)
    let wheel = PampGramDelayWheel(
        units: [
            PampGramWheelUnit(name: "дн", count: 100, seconds: 86400),
            PampGramWheelUnit(name: "ч", count: 24, seconds: 3600),
            PampGramWheelUnit(name: "мин", count: 60, seconds: 60),
            PampGramWheelUnit(name: "с", count: 60, seconds: 1)
        ],
        initialSeconds: Int(initialSeconds),
        textColor: presentationData.theme.actionSheet.primaryTextColor
    )
    sheet.setItemGroups([
        ActionSheetItemGroup(items: [
            ActionSheetTextItem(title: "Сколько будет длиться КД на передачу?"),
            PampGramDelayPickerItem(wheel: wheel),
            ActionSheetButtonItem(title: "Запустить КД", color: .accent, font: .bold, action: { [weak sheet] in
                let seconds = wheel.totalSeconds
                if seconds <= 0 {
                    return
                }
                sheet?.dismissAnimated()
                completion(seconds)
            })
        ]),
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                sheet?.dismissAnimated()
            })
        ])
    ])
    present(sheet)
}
