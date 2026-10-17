import Foundation
import UIKit
import Display

/// The deposit part of the fake CryptoBot: the "Выберите сеть" list (for coins that live on several
/// networks) and the address page with a QR code. The address and the QR are made up: the address
/// is random text in the real format of the chosen network, the QR is a random pattern that looks
/// like one but is not a code anything can scan.

struct PampGramFakeCryptoBotNetwork {
    /// Row title in the network list ("TON", "Tron", "BNB Smart Chain").
    let name: String
    /// Row subtitle ("TON", "TRC20", "SPL").
    let standard: String
    /// What follows the coin in "USDT (TRC20)" and in "через сеть …".
    let short: String
    let assetName: String
}

private let pampGramFakeCryptoBotTonNetwork = PampGramFakeCryptoBotNetwork(name: "TON", standard: "TON", short: "TON", assetName: "net_TON")
private let pampGramFakeCryptoBotTronNetwork = PampGramFakeCryptoBotNetwork(name: "Tron", standard: "TRC20", short: "TRC20", assetName: "coin_TRX")
private let pampGramFakeCryptoBotSolanaNetwork = PampGramFakeCryptoBotNetwork(name: "Solana", standard: "SPL", short: "SPL", assetName: "coin_SOL")
private let pampGramFakeCryptoBotEthereumNetwork = PampGramFakeCryptoBotNetwork(name: "Ethereum", standard: "ERC20", short: "ERC20", assetName: "coin_ETH")
private let pampGramFakeCryptoBotBnbNetwork = PampGramFakeCryptoBotNetwork(name: "BNB Smart Chain", standard: "BEP20", short: "BEP20", assetName: "coin_BNB")

/// The networks a coin can be deposited through. More than one means the network list comes first.
func pampGramFakeCryptoBotNetworks(for code: String) -> [PampGramFakeCryptoBotNetwork] {
    switch code {
    case "USDT", "USDC":
        return [pampGramFakeCryptoBotTonNetwork, pampGramFakeCryptoBotTronNetwork, pampGramFakeCryptoBotSolanaNetwork, pampGramFakeCryptoBotEthereumNetwork, pampGramFakeCryptoBotBnbNetwork]
    case "SOL":
        return [PampGramFakeCryptoBotNetwork(name: "Solana", standard: "SOL", short: "Solana", assetName: "coin_SOL")]
    case "TRX":
        return [PampGramFakeCryptoBotNetwork(name: "Tron", standard: "TRX", short: "Tron", assetName: "coin_TRX")]
    case "BTC":
        return [PampGramFakeCryptoBotNetwork(name: "Bitcoin", standard: "BTC", short: "Bitcoin", assetName: "coin_BTC")]
    case "ETH":
        return [PampGramFakeCryptoBotNetwork(name: "Ethereum", standard: "ERC20", short: "Ethereum", assetName: "coin_ETH")]
    case "DOGE":
        return [PampGramFakeCryptoBotNetwork(name: "Dogecoin", standard: "DOGE", short: "Dogecoin", assetName: "coin_DOGE")]
    case "LTC":
        return [PampGramFakeCryptoBotNetwork(name: "Litecoin", standard: "LTC", short: "Litecoin", assetName: "coin_LTC")]
    case "BNB":
        return [PampGramFakeCryptoBotNetwork(name: "BNB Smart Chain", standard: "BEP20", short: "BNB Smart Chain", assetName: "coin_BNB")]
    case "XAUT":
        return [pampGramFakeCryptoBotEthereumNetwork]
    default:
        return [pampGramFakeCryptoBotTonNetwork]
    }
}

private func pampGramFakeCryptoBotMinimumDeposit(_ code: String) -> String {
    switch code {
    case "GRAM":
        return "0.1"
    case "USDT", "USDC":
        return "1"
    case "SOL":
        return "0.01"
    case "TRX":
        return "5"
    case "BTC":
        return "0.0001"
    case "ETH":
        return "0.001"
    case "DOGE":
        return "10"
    case "LTC":
        return "0.01"
    case "BNB":
        return "0.005"
    default:
        return "0.001"
    }
}

// MARK: - Made-up address and QR

/// A tiny deterministic generator, so the same coin/network/serial always gives the same address.
private struct PampGramFakeCryptoBotRandom {
    private var state: UInt64

    init(seed: String) {
        var hash: UInt64 = 1469598103934665603
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        self.state = hash == 0 ? 88172645463325252 : hash
    }

    mutating func next() -> UInt64 {
        self.state ^= self.state << 13
        self.state ^= self.state >> 7
        self.state ^= self.state << 17
        return self.state
    }

    mutating func pick(_ alphabet: [Character], count: Int) -> String {
        var result = ""
        for _ in 0 ..< count {
            result.append(alphabet[Int(self.next() % UInt64(alphabet.count))])
        }
        return result
    }
}

private let pampGramFakeCryptoBotBase64Url = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
private let pampGramFakeCryptoBotBase58 = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
private let pampGramFakeCryptoBotHex = Array("0123456789abcdefABCDEF")
private let pampGramFakeCryptoBotBech32 = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")

func pampGramFakeCryptoBotAddress(code: String, network: PampGramFakeCryptoBotNetwork, serial: Int) -> String {
    var random = PampGramFakeCryptoBotRandom(seed: code + "|" + network.name + "|" + String(serial) + "|pampgram")
    switch network.name {
    case "TON":
        return "UQ" + random.pick(pampGramFakeCryptoBotBase64Url, count: 46)
    case "Tron":
        return "T" + random.pick(pampGramFakeCryptoBotBase58, count: 33)
    case "Solana":
        return random.pick(pampGramFakeCryptoBotBase58, count: 44)
    case "Ethereum", "BNB Smart Chain":
        return "0x" + random.pick(pampGramFakeCryptoBotHex, count: 40)
    case "Bitcoin":
        return "bc1q" + random.pick(pampGramFakeCryptoBotBech32, count: 38)
    case "Litecoin":
        return "ltc1q" + random.pick(pampGramFakeCryptoBotBech32, count: 38)
    case "Dogecoin":
        return "D" + random.pick(pampGramFakeCryptoBotBase58, count: 33)
    default:
        return "UQ" + random.pick(pampGramFakeCryptoBotBase64Url, count: 46)
    }
}

/// A QR-looking picture: three finder squares and a random fill in blue dots, a free spot in the
/// middle for the logo. The pattern is random, so nothing decodes from it.
final class PampGramFakeCryptoBotQRView: UIView {
    private static let modules = 29
    private var seed = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .white
        self.layer.cornerRadius = 20.0
        self.layer.masksToBounds = true
        self.isOpaque = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSeed(_ seed: String) {
        self.seed = seed
        self.setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let count = PampGramFakeCryptoBotQRView.modules
        let inset: CGFloat = 14.0
        let side = min(self.bounds.width, self.bounds.height) - inset * 2.0
        let module = side / CGFloat(count)
        let blue = UIColor(rgb: 0x3b9de3)
        blue.setFill()
        blue.setStroke()

        func inFinder(_ x: Int, _ y: Int) -> Bool {
            let corner = count - 7
            return (x < 7 && y < 7) || (x >= corner && y < 7) || (x < 7 && y >= corner)
        }

        var random = PampGramFakeCryptoBotRandom(seed: self.seed + "|qr")
        let middle = count / 2
        for y in 0 ..< count {
            for x in 0 ..< count {
                if inFinder(x, y) {
                    continue
                }
                // The middle is left empty for the logo.
                if abs(x - middle) <= 4 && abs(y - middle) <= 4 {
                    continue
                }
                let value = random.next() % 100
                if value < 52 {
                    let dot = CGRect(x: inset + CGFloat(x) * module + module * 0.06, y: inset + CGFloat(y) * module + module * 0.06, width: module * 0.88, height: module * 0.88)
                    UIBezierPath(roundedRect: dot, cornerRadius: module * 0.34).fill()
                }
            }
        }

        let corner = count - 7
        for (fx, fy) in [(0, 0), (corner, 0), (0, corner)] {
            let originX = inset + CGFloat(fx) * module
            let originY = inset + CGFloat(fy) * module
            let outer = CGRect(x: originX + module * 0.5, y: originY + module * 0.5, width: module * 6.0, height: module * 6.0)
            let ring = UIBezierPath(roundedRect: outer, cornerRadius: module * 1.9)
            ring.lineWidth = module
            ring.stroke()
            let inner = CGRect(x: originX + module * 2.0, y: originY + module * 2.0, width: module * 3.0, height: module * 3.0)
            UIBezierPath(roundedRect: inner, cornerRadius: module * 0.9).fill()
        }
    }
}

/// The small cut-gem shape of the faint pattern beside the QR.
private final class PampGramFakeCryptoBotGemView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        let w = self.bounds.width
        let h = self.bounds.height
        let gem = UIBezierPath()
        gem.move(to: CGPoint(x: w * 0.24, y: h * 0.06))
        gem.addLine(to: CGPoint(x: w * 0.76, y: h * 0.06))
        gem.addLine(to: CGPoint(x: w * 0.98, y: h * 0.36))
        gem.addLine(to: CGPoint(x: w * 0.5, y: h * 0.96))
        gem.addLine(to: CGPoint(x: w * 0.02, y: h * 0.36))
        gem.close()
        gem.lineJoinStyle = .round
        UIColor(rgb: 0x1b3a54).setFill()
        gem.fill()

        let star = UIBezierPath()
        let cx = w * 0.5
        let cy = h * 0.42
        let arm = w * 0.2
        let waist = w * 0.05
        star.move(to: CGPoint(x: cx, y: cy - arm))
        star.addLine(to: CGPoint(x: cx + waist, y: cy - waist))
        star.addLine(to: CGPoint(x: cx + arm, y: cy))
        star.addLine(to: CGPoint(x: cx + waist, y: cy + waist))
        star.addLine(to: CGPoint(x: cx, y: cy + arm))
        star.addLine(to: CGPoint(x: cx - waist, y: cy + waist))
        star.addLine(to: CGPoint(x: cx - arm, y: cy))
        star.addLine(to: CGPoint(x: cx - waist, y: cy - waist))
        star.close()
        UIColor(rgb: 0x0f2232).setFill()
        star.fill()
    }
}

/// "Пополнить с TON кошелька ↗" and the like: a small blue square with a glyph, a title and a
/// grey arrow (or none).
private final class PampGramFakeCryptoBotActionRowView: UIControl {
    private let badge = UIView()
    private let glyph = UIImageView()
    private let titleLabel = UILabel()
    private let arrow = UIImageView()
    private let separator = UIView()

    init(title: String, glyphImage: UIImage?, accent: Bool, showsArrow: Bool, showsSeparator: Bool) {
        super.init(frame: .zero)
        self.badge.backgroundColor = UIColor(rgb: 0x419de0)
        self.badge.layer.cornerRadius = 7.0
        self.badge.isUserInteractionEnabled = false
        self.addSubview(self.badge)

        self.glyph.image = glyphImage?.withRenderingMode(.alwaysTemplate)
        self.glyph.tintColor = .white
        self.glyph.contentMode = .scaleAspectFit
        self.glyph.isUserInteractionEnabled = false
        self.badge.addSubview(self.glyph)

        self.titleLabel.text = title
        self.titleLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .regular)
        self.titleLabel.textColor = accent ? UIColor(rgb: 0x3b9de3) : .white
        self.titleLabel.isUserInteractionEnabled = false
        self.addSubview(self.titleLabel)

        self.arrow.image = UIImage(systemName: "arrow.up.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13.0, weight: .semibold))
        self.arrow.tintColor = UIColor(rgb: 0x959595)
        self.arrow.contentMode = .center
        self.arrow.isHidden = !showsArrow
        self.arrow.isUserInteractionEnabled = false
        self.addSubview(self.arrow)

        self.separator.backgroundColor = UIColor(rgb: 0x292929)
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
        self.badge.frame = CGRect(x: 16.0, y: floor((height - 28.0) / 2.0), width: 28.0, height: 28.0)
        self.glyph.frame = self.badge.bounds.insetBy(dx: 5.0, dy: 5.0)
        self.titleLabel.frame = CGRect(x: 56.0, y: floor((height - 22.0) / 2.0), width: max(0.0, width - 56.0 - 44.0), height: 22.0)
        self.arrow.frame = CGRect(x: width - 16.0 - 16.0, y: floor((height - 16.0) / 2.0), width: 16.0, height: 16.0)
        self.separator.frame = CGRect(x: 56.0, y: height - 1.0, width: max(0.0, width - 56.0 - 16.0), height: 1.0)
    }

    override var isHighlighted: Bool {
        didSet {
            self.alpha = self.isHighlighted ? 0.6 : 1.0
        }
    }
}

// MARK: - The address page

final class PampGramFakeCryptoBotAddressView: UIScrollView {
    var onCopy: ((String) -> Void)?
    var onUnavailable: (() -> Void)?
    var onNewAddress: (() -> Void)?

    private let qrView = PampGramFakeCryptoBotQRView()
    private let qrLogoRing = UIView()
    private let qrLogo = UIImageView()
    private let gearControl = UIControl()
    private let gearIcon = UIImageView()
    private var gems: [PampGramFakeCryptoBotGemView] = []
    private let titleLabel = UILabel()
    private let networkLabel = UILabel()
    private let cardView = UIView()
    private let coinIcon = UIImageView()
    private let badgeRing = UIView()
    private let badgeIcon = UIImageView()
    private let addressLabel = UILabel()
    private let copyControl = UIControl()
    private let copyIcon = UIImageView()
    private let minStrip = UIView()
    private let minLabel = UILabel()
    private let noteOne = UILabel()
    private let noteTwo = UILabel()
    private var rows: [PampGramFakeCryptoBotActionRowView] = []
    private var rowKinds: [Int] = []

    private var address = ""
    private var showsWalletRow = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.showsVerticalScrollIndicator = false
        self.alwaysBounceVertical = true

        for _ in 0 ..< 10 {
            let gem = PampGramFakeCryptoBotGemView()
            self.addSubview(gem)
            self.gems.append(gem)
        }
        self.addSubview(self.qrView)

        self.qrLogoRing.backgroundColor = .white
        self.qrLogoRing.isUserInteractionEnabled = false
        self.addSubview(self.qrLogoRing)
        self.qrLogo.contentMode = .scaleAspectFit
        self.qrLogo.isUserInteractionEnabled = false
        self.addSubview(self.qrLogo)

        self.gearControl.backgroundColor = UIColor(rgb: 0x262626)
        self.gearControl.layer.cornerRadius = 16.0
        self.gearControl.addTarget(self, action: #selector(self.unavailablePressed), for: .touchUpInside)
        self.gearIcon.image = UIImage(systemName: "gearshape", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17.0, weight: .regular))
        self.gearIcon.tintColor = UIColor(rgb: 0x9a9a9a)
        self.gearIcon.contentMode = .center
        self.gearIcon.isUserInteractionEnabled = false
        self.gearControl.addSubview(self.gearIcon)
        self.addSubview(self.gearControl)

        self.titleLabel.text = "Мой адрес"
        self.titleLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .medium)
        self.titleLabel.textColor = .white
        self.addSubview(self.titleLabel)

        self.networkLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .regular)
        self.networkLabel.textColor = UIColor(rgb: 0x959595)
        self.networkLabel.textAlignment = .right
        self.addSubview(self.networkLabel)

        self.cardView.backgroundColor = UIColor(rgb: 0x171717)
        self.cardView.layer.cornerRadius = 14.0
        self.cardView.layer.borderWidth = 1.0
        self.cardView.layer.borderColor = UIColor(rgb: 0x2b2b2b).cgColor
        self.cardView.layer.masksToBounds = true
        self.addSubview(self.cardView)

        self.minStrip.backgroundColor = UIColor(rgb: 0x1f1f1f)
        self.cardView.addSubview(self.minStrip)
        self.minLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .regular)
        self.minLabel.textColor = UIColor(rgb: 0x959595)
        self.minStrip.addSubview(self.minLabel)

        self.coinIcon.contentMode = .scaleAspectFit
        self.cardView.addSubview(self.coinIcon)
        self.badgeRing.backgroundColor = UIColor(rgb: 0x171717)
        self.badgeRing.layer.cornerRadius = 11.0
        self.cardView.addSubview(self.badgeRing)
        self.badgeIcon.contentMode = .scaleAspectFit
        self.cardView.addSubview(self.badgeIcon)

        self.addressLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .regular)
        self.addressLabel.textColor = .white
        self.addressLabel.numberOfLines = 2
        self.addressLabel.lineBreakMode = .byCharWrapping
        self.cardView.addSubview(self.addressLabel)

        self.copyIcon.image = UIImage(systemName: "square.on.square", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19.0, weight: .regular))
        self.copyIcon.tintColor = UIColor(rgb: 0x3b9de3)
        self.copyIcon.contentMode = .center
        self.copyIcon.isUserInteractionEnabled = false
        self.copyControl.addSubview(self.copyIcon)
        self.copyControl.addTarget(self, action: #selector(self.copyPressed), for: .touchUpInside)
        self.cardView.addSubview(self.copyControl)

        self.noteOne.numberOfLines = 0
        self.noteTwo.numberOfLines = 0
        self.addSubview(self.noteOne)
        self.addSubview(self.noteTwo)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(currency: PampGramFakeCryptoBotCurrency, network: PampGramFakeCryptoBotNetwork, serial: Int) {
        self.address = pampGramFakeCryptoBotAddress(code: currency.code, network: network, serial: serial)
        self.qrView.setSeed(self.address)
        let networkImage = PampGramFakeCryptoBotAssets.image(network.assetName)
        self.qrLogo.image = networkImage
        self.networkLabel.text = currency.code + " (" + network.short + ")"
        self.coinIcon.image = PampGramFakeCryptoBotAssets.image(currency.assetName)
        let showsBadge = network.assetName != currency.assetName
        self.badgeIcon.image = showsBadge ? networkImage : nil
        self.badgeRing.isHidden = !showsBadge
        self.badgeIcon.isHidden = !showsBadge
        self.addressLabel.text = self.address
        self.minLabel.text = "Мин. пополнение: " + pampGramFakeCryptoBotMinimumDeposit(currency.code) + " " + currency.code
        self.noteOne.attributedText = self.noteOneText(currency: currency, network: network)
        self.noteTwo.attributedText = self.noteTwoText()

        for row in self.rows {
            row.removeFromSuperview()
        }
        self.rows.removeAll()
        self.rowKinds.removeAll()
        self.showsWalletRow = network.name == "TON"
        var specs: [(String, UIImage?, Bool, Bool, Int)] = []
        if self.showsWalletRow {
            specs.append(("Пополнить с TON кошелька", PampGramFakeCryptoBotAssets.image("tab_wallet"), false, true, 0))
        }
        specs.append(("Открыть в обозревателе", UIImage(systemName: "globe", withConfiguration: UIImage.SymbolConfiguration(pointSize: 40.0, weight: .regular)), false, true, 1))
        specs.append(("Поделиться адресом", UIImage(systemName: "arrowshape.turn.up.right.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 40.0, weight: .regular)), false, true, 2))
        specs.append(("Получить новый адрес", UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 40.0, weight: .semibold)), true, false, 3))
        for (index, spec) in specs.enumerated() {
            let row = PampGramFakeCryptoBotActionRowView(title: spec.0, glyphImage: spec.1, accent: spec.2, showsArrow: spec.3, showsSeparator: index < specs.count - 1)
            row.tag = spec.4
            row.addTarget(self, action: #selector(self.rowPressed(_:)), for: .touchUpInside)
            self.addSubview(row)
            self.rows.append(row)
        }
        self.contentOffset = .zero
        self.setNeedsLayout()
    }

    private func coinAttachment(_ image: UIImage?) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0.0, y: -4.5, width: 20.0, height: 20.0)
        return NSAttributedString(attachment: attachment)
    }

    private func noteOneText(currency: PampGramFakeCryptoBotCurrency, network: PampGramFakeCryptoBotNetwork) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15.0, weight: .regular),
            .foregroundColor: UIColor(rgb: 0x959595)
        ]
        let text = NSMutableAttributedString(string: "Отправляйте только ", attributes: attributes)
        text.append(self.coinAttachment(PampGramFakeCryptoBotAssets.image(currency.assetName)))
        text.append(NSAttributedString(string: " " + currency.code + " через сеть ", attributes: attributes))
        text.append(self.coinAttachment(PampGramFakeCryptoBotAssets.image(network.assetName)))
        text.append(NSAttributedString(string: " " + network.short + ", иначе монеты будут утеряны.", attributes: attributes))
        return text
    }

    private func noteTwoText() -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15.0, weight: .regular),
            .foregroundColor: UIColor(rgb: 0x959595)
        ]
        let text = NSMutableAttributedString(string: "Перевод из санкционных и высокорисковых сервисов может быть отменён. ", attributes: attributes)
        text.append(NSAttributedString(string: "Подробнее ›", attributes: [
            .font: UIFont.systemFont(ofSize: 15.0, weight: .regular),
            .foregroundColor: UIColor(rgb: 0x3b9de3)
        ]))
        return text
    }

    @objc private func copyPressed() {
        self.onCopy?(self.address)
    }

    @objc private func unavailablePressed() {
        self.onUnavailable?()
    }

    @objc private func rowPressed(_ sender: PampGramFakeCryptoBotActionRowView) {
        switch sender.tag {
        case 3:
            self.onNewAddress?()
        default:
            self.onUnavailable?()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width

        let qrSize: CGFloat = 160.0
        self.qrView.frame = CGRect(x: floor((width - qrSize) / 2.0), y: 25.0, width: qrSize, height: qrSize)
        let ringSize: CGFloat = 46.0
        self.qrLogoRing.frame = CGRect(x: self.qrView.frame.midX - ringSize / 2.0, y: self.qrView.frame.midY - ringSize / 2.0, width: ringSize, height: ringSize)
        self.qrLogoRing.layer.cornerRadius = ringSize / 2.0
        let logoSize: CGFloat = 38.0
        self.qrLogo.frame = CGRect(x: self.qrView.frame.midX - logoSize / 2.0, y: self.qrView.frame.midY - logoSize / 2.0, width: logoSize, height: logoSize)
        self.gearControl.frame = CGRect(x: width - 16.0 - 32.0, y: 9.0, width: 32.0, height: 32.0)
        self.gearIcon.frame = self.gearControl.bounds

        // The faint pattern: five gems on each side of the QR, getting smaller outwards.
        let leftSpots: [(CGFloat, CGFloat, CGFloat)] = [(89.0, 57.0, 17.0), (56.0, 79.0, 14.0), (30.0, 105.0, 11.0), (56.0, 131.0, 14.0), (89.0, 153.0, 17.0)]
        for (index, spot) in leftSpots.enumerated() {
            let size = spot.2
            self.gems[index].frame = CGRect(x: spot.0 - size / 2.0, y: spot.1 - size / 2.0, width: size, height: size)
            self.gems[index + 5].frame = CGRect(x: width - spot.0 - size / 2.0, y: spot.1 - size / 2.0, width: size, height: size)
        }

        self.titleLabel.frame = CGRect(x: 16.0, y: 239.0, width: 160.0, height: 22.0)
        self.networkLabel.frame = CGRect(x: width - 16.0 - 200.0, y: 240.0, width: 200.0, height: 20.0)

        let cardWidth = width - 32.0
        self.cardView.frame = CGRect(x: 16.0, y: 273.0, width: cardWidth, height: 101.0)
        self.coinIcon.frame = CGRect(x: 13.0, y: 14.0, width: 40.0, height: 40.0)
        self.badgeRing.frame = CGRect(x: 13.0 + 26.0, y: 14.0 + 26.0, width: 22.0, height: 22.0)
        self.badgeIcon.frame = self.badgeRing.frame.insetBy(dx: 2.0, dy: 2.0)
        self.addressLabel.frame = CGRect(x: 66.0, y: 13.0, width: cardWidth - 66.0 - 46.0, height: 44.0)
        self.copyControl.frame = CGRect(x: cardWidth - 46.0, y: 0.0, width: 46.0, height: 68.0)
        self.copyIcon.frame = self.copyControl.bounds
        self.minStrip.frame = CGRect(x: 0.0, y: 68.0, width: cardWidth, height: 33.0)
        self.minLabel.frame = CGRect(x: 13.0, y: 6.0, width: cardWidth - 26.0, height: 21.0)

        let noteWidth = width - 32.0
        let oneSize = self.noteOne.sizeThatFits(CGSize(width: noteWidth, height: CGFloat.greatestFiniteMagnitude))
        self.noteOne.frame = CGRect(x: 16.0, y: 393.0, width: noteWidth, height: ceil(oneSize.height))
        let twoSize = self.noteTwo.sizeThatFits(CGSize(width: noteWidth, height: CGFloat.greatestFiniteMagnitude))
        self.noteTwo.frame = CGRect(x: 16.0, y: self.noteOne.frame.maxY + 10.0, width: noteWidth, height: ceil(twoSize.height))

        var y = self.noteTwo.frame.maxY + 24.0
        for row in self.rows {
            row.frame = CGRect(x: 0.0, y: y, width: width, height: 52.0)
            y += 52.0
        }
        self.contentSize = CGSize(width: width, height: y + 90.0)
    }
}
