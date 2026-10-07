import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData

/// Human wording for a delay picked with the wheels: "через 1 ч 5 мин 30 с".
public func pampGramGiftDelayDescription(seconds: Int32) -> String {
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    var parts: [String] = []
    if hours != 0 {
        parts.append("\(hours) ч")
    }
    if minutes != 0 {
        parts.append("\(minutes) мин")
    }
    if secs != 0 || parts.isEmpty {
        parts.append("\(secs) с")
    }
    return "через " + parts.joined(separator: " ")
}

/// The three wheels (hours / minutes / seconds) of the system Clock timer. The unit label is shown
/// next to the number only on the row that is currently selected, like in the Clock app.
private final class PampGramDelayWheel: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
    private static let units = ["ч", "мин", "с"]
    private static let counts = [100, 60, 60]

    private let textColor: UIColor
    private let secondaryColor: UIColor
    var selected: [Int] = [0, 5, 0]

    init(textColor: UIColor, secondaryColor: UIColor) {
        self.textColor = textColor
        self.secondaryColor = secondaryColor
        super.init()
    }

    var totalSeconds: Int32 {
        return Int32(self.selected[0] * 3600 + self.selected[1] * 60 + self.selected[2])
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 3
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return PampGramDelayWheel.counts[component]
    }

    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
        return 40.0
    }

    func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
        let width = pickerView.bounds.width / 3.0
        let container = (view as? PampGramDelayWheelRow) ?? PampGramDelayWheelRow(frame: CGRect(x: 0.0, y: 0.0, width: width, height: 40.0))
        container.frame = CGRect(x: 0.0, y: 0.0, width: width, height: 40.0)
        let isSelected = self.selected[component] == row
        container.update(number: "\(row)", unit: isSelected ? PampGramDelayWheel.units[component] : nil, textColor: self.textColor, unitColor: self.secondaryColor)
        return container
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        self.selected[component] = row
        pickerView.reloadComponent(component)
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

    func update(number: String, unit: String?, textColor: UIColor, unitColor: UIColor) {
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
            for component in 0 ..< 3 {
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
    let wheel = PampGramDelayWheel(textColor: presentationData.theme.actionSheet.primaryTextColor, secondaryColor: presentationData.theme.actionSheet.secondaryTextColor)
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
