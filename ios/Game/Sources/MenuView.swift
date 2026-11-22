import UIKit

/// 原版“菜单”弹窗（高手排行榜 / 成就列表 / 声音 / 震动 / 购买点数 …）
final class MenuView: UIView, UIGestureRecognizerDelegate {

    var onRedeem: (() -> Void)?
    var onHelp: (() -> Void)?
    var onClose: (() -> Void)?
    var onRank: (() -> Void)?
    var onAchievements: (() -> Void)?
    var onFreePoints: (() -> Void)?
    var onExchangePoints: (() -> Void)?
    var onMore: (() -> Void)?

    private let panel = UIView()
    private let titleLabel = UILabel()
    private let tipLabel = UILabel()

    private let leaderButton = UIButton(type: .system)
    private let achievementButton = UIButton(type: .system)
    private let soundButton = UIButton(type: .system)
    private let vibrateButton = UIButton(type: .system)
    private let buyButton = UIButton(type: .system)
    private let freeButton = UIButton(type: .system)
    private let exchangeButton = UIButton(type: .system)
    private let helpButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)

    private let goldColor = UIColor(red: 0xf5 / 255.0, green: 0xc4 / 255.0, blue: 0x51 / 255.0, alpha: 1)
    private let textColor = UIColor(red: 0xe9 / 255.0, green: 0xdc / 255.0, blue: 0xc0 / 255.0, alpha: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        backgroundColor = UIColor(white: 0, alpha: 0.55)

        panel.backgroundColor = UIColor(red: 0x17 / 255.0, green: 0x13 / 255.0, blue: 0x0f / 255.0, alpha: 0.97)
        panel.layer.cornerRadius = 10
        panel.layer.borderWidth = 1
        panel.layer.borderColor = UIColor(red: 0x6b / 255.0, green: 0x5a / 255.0, blue: 0x3a / 255.0, alpha: 1).cgColor
        addSubview(panel)

        titleLabel.textColor = goldColor
        titleLabel.font = UIFont.boldSystemFont(ofSize: 16)
        titleLabel.textAlignment = .center
        panel.addSubview(titleLabel)

        configure(leaderButton, title: "高手排行榜")
        configure(achievementButton, title: "成就列表")
        configure(soundButton, title: soundTitle())
        configure(vibrateButton, title: vibrateTitle())
        configure(buyButton, title: "直接购买点数")
        configure(freeButton, title: "免费获取积分")
        configure(exchangeButton, title: "积分兑换点数")
        configure(helpButton, title: "帮助")
        configure(moreButton, title: "更多游戏")
        configure(backButton, title: "返回游戏", gold: true)

        leaderButton.addTarget(self, action: #selector(leaderTapped), for: .touchUpInside)
        achievementButton.addTarget(self, action: #selector(achievementTapped), for: .touchUpInside)
        soundButton.addTarget(self, action: #selector(soundTapped), for: .touchUpInside)
        vibrateButton.addTarget(self, action: #selector(vibrateTapped), for: .touchUpInside)
        buyButton.addTarget(self, action: #selector(buyTapped), for: .touchUpInside)
        freeButton.addTarget(self, action: #selector(freeTapped), for: .touchUpInside)
        exchangeButton.addTarget(self, action: #selector(exchangeTapped), for: .touchUpInside)
        helpButton.addTarget(self, action: #selector(helpTapped), for: .touchUpInside)
        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        tipLabel.textColor = .white
        tipLabel.font = UIFont.systemFont(ofSize: 13)
        tipLabel.textAlignment = .center
        tipLabel.backgroundColor = UIColor(white: 0, alpha: 0.8)
        tipLabel.layer.cornerRadius = 6
        tipLabel.layer.masksToBounds = true
        tipLabel.alpha = 0
        addSubview(tipLabel)

        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        addGestureRecognizer(tap)

        updateTitle()
    }

    private func configure(_ button: UIButton, title: String, gold: Bool = false) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(gold ? .black : textColor, for: .normal)
        button.titleLabel?.font = gold
            ? UIFont.boldSystemFont(ofSize: 16)
            : UIFont.systemFont(ofSize: 15)
        button.backgroundColor = gold
            ? goldColor
            : UIColor(red: 0x24 / 255.0, green: 0x1f / 255.0, blue: 0x18 / 255.0, alpha: 1)
        button.layer.cornerRadius = 5
        if !gold {
            button.layer.borderWidth = 1
            button.layer.borderColor = UIColor(red: 0x5c / 255.0, green: 0x4d / 255.0, blue: 0x33 / 255.0, alpha: 1).cgColor
        }
        panel.addSubview(button)
    }

    private func soundTitle() -> String {
        return GameModel.shared.soundDisabled ? "开启声音" : "关闭声音"
    }

    private func vibrateTitle() -> String {
        return GameModel.shared.vibrateDisabled ? "开启震动" : "关闭震动"
    }

    func updateTitle() {
        titleLabel.text = "当前积分：\(LHJWebViewController.playerPoints)"
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let panelWidth = min(360, bounds.width - 36)
        let padding: CGFloat = 16
        let rowHeight: CGFloat = 44
        let gap: CGFloat = 10
        let titleHeight: CGFloat = 34
        let rows: [[UIButton]] = [
            [leaderButton, achievementButton],
            [soundButton, vibrateButton],
            [buyButton],
            [freeButton, exchangeButton],
            [helpButton, moreButton],
            [backButton]
        ]
        let panelHeight = padding + titleHeight + 10
            + CGFloat(rows.count) * rowHeight
            + CGFloat(rows.count - 1) * gap
            + padding

        panel.frame = CGRect(x: (bounds.width - panelWidth) / 2,
                             y: (bounds.height - panelHeight) / 2,
                             width: panelWidth, height: panelHeight)
        titleLabel.frame = CGRect(x: padding, y: padding,
                                  width: panelWidth - padding * 2, height: titleHeight)

        var y = padding + titleHeight + 10
        let columnWidth = (panelWidth - padding * 2 - gap) / 2
        for row in rows {
            if row.count == 1 {
                row[0].frame = CGRect(x: padding, y: y,
                                      width: panelWidth - padding * 2, height: rowHeight)
            } else {
                row[0].frame = CGRect(x: padding, y: y, width: columnWidth, height: rowHeight)
                row[1].frame = CGRect(x: padding + columnWidth + gap, y: y,
                                      width: columnWidth, height: rowHeight)
            }
            y += rowHeight + gap
        }

        tipLabel.frame = CGRect(x: (bounds.width - 240) / 2,
                                y: panel.frame.maxY + 14,
                                width: 240, height: 32)
    }

    private func showTip(_ text: String) {
        tipLabel.text = text
        tipLabel.alpha = 0
        UIView.animate(withDuration: 0.15, animations: {
            self.tipLabel.alpha = 1
        }, completion: { _ in
            UIView.animate(withDuration: 0.25, delay: 1.1, options: [], animations: {
                self.tipLabel.alpha = 0
            }, completion: nil)
        })
    }

    // MARK: - 按钮

    @objc private func leaderTapped() { onRank?() }
    @objc private func achievementTapped() { onAchievements?() }

    @objc private func soundTapped() {
        GameModel.shared.soundDisabled.toggle()
        SoundPlayer.shared.enabled = !GameModel.shared.soundDisabled
        soundButton.setTitle(soundTitle(), for: .normal)
        if !GameModel.shared.soundDisabled { SoundPlayer.shared.play("in") }
    }

    @objc private func vibrateTapped() {
        GameModel.shared.vibrateDisabled.toggle()
        vibrateButton.setTitle(vibrateTitle(), for: .normal)
    }

    @objc private func buyTapped() { onRedeem?() }
    @objc private func helpTapped() { onHelp?() }
    @objc private func freeTapped() { onFreePoints?() }
    @objc private func exchangeTapped() { onExchangePoints?() }
    @objc private func moreTapped() { onMore?() }
    @objc private func backTapped() { onClose?() }

    @objc private func backgroundTapped(_ gesture: UITapGestureRecognizer) {
        onClose?()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        return !panel.frame.contains(touch.location(in: self))
    }
}
