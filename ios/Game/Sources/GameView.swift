import UIKit
import QuartzCore

protocol GameViewDelegate: AnyObject {
    func gameViewDidRequestMenu(_ view: GameView)
}

/// 完全自绘的游戏盘面（对应安卓 GameBody.a(Canvas)）
final class GameView: UIView {

    weak var delegate: GameViewDelegate?

    private enum Phase: Equatable {
        case idle
        case spinning
        case result
        case gamble
    }

    // MARK: - 设计稿常量

    private static let designSize = CGSize(width: 480, height: 730)

    // 24 个格的贴图（mask.png 60x57）左上角坐标
    private static let tiles: [CGPoint] = {
        var points = [CGPoint](repeating: .zero, count: 24)
        for i in 0..<24 {
            var x: CGFloat = 12
            var y: CGFloat = 88
            if i <= 6 {
                x = 12 + CGFloat(i) * 66
                y = 88
            } else if i <= 11 {
                x = 409
                y = 91 + CGFloat(i - 6) * 66
            } else if i <= 18 {
                x = 12 + CGFloat(18 - i) * 66
                y = 491
            } else {
                x = CGFloat(12 - (i - 18))
                y = 91 + CGFloat(6 - (i - 18)) * 66
            }
            points[i] = CGPoint(x: x, y: y)
        }
        return points
    }()

    // 跑灯位置（on.png 24x24 左上角）
    private static let lamps: [CGPoint] = [
        CGPoint(x: 72, y: 144), CGPoint(x: 102, y: 144), CGPoint(x: 162, y: 144),
        CGPoint(x: 228, y: 144), CGPoint(x: 294, y: 144), CGPoint(x: 354, y: 144),
        CGPoint(x: 384, y: 144),
        CGPoint(x: 384, y: 174), CGPoint(x: 384, y: 240), CGPoint(x: 384, y: 306),
        CGPoint(x: 384, y: 372), CGPoint(x: 384, y: 438),
        CGPoint(x: 384, y: 468),
        CGPoint(x: 354, y: 468), CGPoint(x: 294, y: 468), CGPoint(x: 228, y: 468),
        CGPoint(x: 162, y: 468), CGPoint(x: 102, y: 468), CGPoint(x: 72, y: 468),
        CGPoint(x: 72, y: 438), CGPoint(x: 72, y: 372), CGPoint(x: 72, y: 306),
        CGPoint(x: 72, y: 240), CGPoint(x: 72, y: 174)
    ]

    // 8 个投注格数字显示位置（右对齐边）
    private static let chipX: [CGFloat] = [59, 116, 173, 230, 287, 344, 401, 458]
    // 投注格点击分界
    private static let chipHitX: [CGFloat] = [30, 87, 144, 201, 258, 315, 373, 430]

    private let startRect = CGRect(x: 336, y: 672, width: 133, height: 53)
    private let smallRect = CGRect(x: 10, y: 672, width: 90, height: 53)
    private let bigRect = CGRect(x: 106, y: 672, width: 89, height: 53)
    private let menuRect = CGRect(x: 222, y: 672, width: 93, height: 53)
    private let scorePanelRect = CGRect(x: 259, y: 2, width: 203, height: 68)
    private let winPanelRect = CGRect(x: 25, y: 2, width: 195, height: 68)

    // MARK: - 资源

    private let model = GameModel.shared

    private lazy var boardImage = UIImage(named: "ok.png") ?? UIImage(named: "ok")
    private lazy var lampImage = UIImage(named: "on.png") ?? UIImage(named: "on")
    private lazy var maskImage = UIImage(named: "mask.png") ?? UIImage(named: "mask")
    private lazy var bannerDasy = UIImage(named: "dasy.png") ?? UIImage(named: "dasy")
    private lazy var bannerDamg = UIImage(named: "damg.png") ?? UIImage(named: "damg")
    private lazy var bannerKaihc = UIImage(named: "kaihc.png") ?? UIImage(named: "kaihc")
    private lazy var digitImages: [UIImage] = {
        guard let sheet = UIImage(named: "num_big.png") ?? UIImage(named: "num_big"),
              let cg = sheet.cgImage else { return [] }
        let sliceWidth = cg.width / 11
        var images: [UIImage] = []
        for index in 0..<10 {
            guard let slice = cg.cropping(to: CGRect(x: index * sliceWidth, y: 0,
                                                     width: sliceWidth, height: cg.height)) else { continue }
            images.append(UIImage(cgImage: slice, scale: 1, orientation: .up))
        }
        return images
    }()

    // MARK: - 状态

    private var scaleX: CGFloat = 1
    private var scaleY: CGFloat = 1
    private var offset: CGPoint = .zero

    private var phase: Phase = .idle
    private var lampIndex: Int = 0
    private var lampBlink: Bool = true

    private var displayLink: CADisplayLink?
    private var idleTick: CFTimeInterval = 0
    private var lastFrameTime: CFTimeInterval = 0

    private var spinStartTime: CFTimeInterval = 0
    private var spinDuration: CFTimeInterval = 3.0
    private var spinSteps: Int = 40
    private var spinStartIndex: Int = 0
    private var spinLanding: Int = 0
    private var outcome: GameModel.Outcome?

    private var resultStartTime: CFTimeInterval = 0
    private var resultPositions: [Int] = []

    // 押大小
    private var gambleStartTime: CFTimeInterval = 0
    private var gambleBig = false
    private var gambleText: String = ""

    private let toastLabel = UILabel()

    // MARK: - 初始化

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isMultipleTouchEnabled = false
        setUpToast()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        setUpToast()
    }

    deinit {
        displayLink?.invalidate()
    }

    private func setUpToast() {
        toastLabel.backgroundColor = UIColor(white: 0, alpha: 0.75)
        toastLabel.textColor = .white
        toastLabel.font = UIFont.systemFont(ofSize: 14)
        toastLabel.textAlignment = .center
        toastLabel.layer.cornerRadius = 8
        toastLabel.layer.masksToBounds = true
        toastLabel.alpha = 0
        addSubview(toastLabel)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startDisplayLink()
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastFrameTime = CACurrentMediaTime()
        idleTick = lastFrameTime
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let topInset = safeAreaInsets.top
        scaleX = bounds.width / GameView.designSize.width
        scaleY = max(0.1, (bounds.height - topInset) / GameView.designSize.height)
        offset = CGPoint(x: 0, y: topInset)
        toastLabel.frame = CGRect(x: bounds.midX - 110,
                                  y: bounds.height - 140,
                                  width: 220, height: 36)
        setNeedsDisplay()
    }

    // MARK: - 帧循环

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let dt = now - lastFrameTime
        lastFrameTime = now
        if dt > 0.25 { return }

        switch phase {
        case .idle, .result:
            idleTick += dt
            if idleTick >= 0.24 {
                idleTick = 0
                lampBlink.toggle()
            }
        case .gamble:
            let elapsed = now - gambleStartTime
            gambleText = (Int(elapsed * 12) % 2 == 0) ? "大" : "小"
            if elapsed >= 1.6 {
                resolveGamble()
            }
        case .spinning:
            let progress = min(1, (now - spinStartTime) / spinDuration)
            let eased = 1 - pow(1 - progress, 3)
            let step = Int(Double(spinSteps) * eased)
            lampIndex = (spinStartIndex + step) % 24
            if progress >= 1 {
                finishSpin(now: now)
            }
        }
        setNeedsDisplay()
    }

    private func finishSpin(now: CFTimeInterval) {
        lampIndex = spinLanding
        lampBlink = true
        SoundPlayer.shared.stop("loop")

        guard let outcome = outcome else {
            phase = .idle
            return
        }

        if outcome.payout > 0 {
            phase = .result
            resultStartTime = now
            resultPositions = outcome.positions
            model.setWin(outcome.payout)

            if !model.vibrateDisabled {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            switch outcome.type {
            case 17:
                SoundPlayer.shared.play("bswin")
            case 20, 22:
                SoundPlayer.shared.play("bs")
                SoundPlayer.shared.play("boom")
            default:
                SoundPlayer.shared.play("win")
            }
        } else {
            phase = .idle
            resultPositions = []
        }
        setNeedsDisplay()
    }

    // MARK: - 绘制

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(bounds)

        ctx.saveGState()
        ctx.translateBy(x: offset.x, y: offset.y)
        ctx.scaleBy(x: scaleX, y: scaleY)

        boardImage?.draw(in: CGRect(origin: .zero, size: GameView.designSize))

        // 中奖金额、剩余点数（各 10 位，补零）
        drawNumber(model.win, rightEdge: 219, y: 32, minDigits: 10, spacing: 0)
        drawNumber(model.score, rightEdge: 457, y: 32, minDigits: 10, spacing: 0)

        // 8 个投注格
        for i in 0..<8 {
            drawNumber(Int64(model.bets[i]),
                       rightEdge: GameView.chipX[7 - i],
                       y: 621, minDigits: 2, spacing: 1)
        }

        // 总注
        drawNumber(Int64(model.totalBet), rightEdge: 257, y: 383, minDigits: 2, spacing: 2)

        // 跑灯
        if lampBlink, lampIndex >= 0, lampIndex < GameView.lamps.count {
            let p = GameView.lamps[lampIndex]
            lampImage?.draw(in: CGRect(x: p.x, y: p.y, width: 24, height: 24))
        }

        // 中奖高亮 + 大奖项横幅
        if phase == .result || phase == .gamble {
            for index in resultPositions {
                guard index >= 0, index < GameView.tiles.count else { continue }
                let p = GameView.tiles[index]
                maskImage?.draw(in: CGRect(x: p.x, y: p.y, width: 60, height: 57))
            }
            if phase == .result {
                drawBanner(now: CACurrentMediaTime())
            }
        }

        if phase == .gamble {
            drawGamble()
        }

        ctx.restoreGState()
    }

    private func drawBanner(now: CFTimeInterval) {
        guard let outcome = outcome else { return }
        let image: UIImage?
        switch outcome.type {
        case 17: image = bannerDasy
        case 20: image = bannerDamg
        case 22: image = bannerKaihc
        default: image = nil
        }
        guard let banner = image else { return }

        let elapsed = max(0, now - resultStartTime)
        let alpha = min(1, elapsed / 0.25)
        let scaleFactor = 0.85 + 0.15 * min(1, elapsed / 0.3)
        let w = banner.size.width * scaleFactor
        let h = banner.size.height * scaleFactor
        let rect = CGRect(x: 240 - w / 2, y: 400 - h / 2, width: w, height: h)
        banner.draw(in: rect, blendMode: .normal, alpha: alpha)
    }

    private func drawGamble() {
        let box = CGRect(x: 70, y: 270, width: 340, height: 190)
        let path = UIBezierPath(roundedRect: box, cornerRadius: 12)
        UIColor(white: 0, alpha: 0.72).setFill()
        path.fill()
        UIColor(red: 0xf5 / 255.0, green: 0xc4 / 255.0, blue: 0x51 / 255.0, alpha: 0.8).setStroke()
        path.lineWidth = 2
        path.stroke()

        let hint = "押\(gambleBig ? "大" : "小")：赢则翻倍"
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: UIColor(red: 0xe8 / 255.0, green: 0xd9 / 255.0, blue: 0xb0 / 255.0, alpha: 1)
        ]
        let hintSize = (hint as NSString).size(withAttributes: hintAttrs)
        (hint as NSString).draw(at: CGPoint(x: 240 - hintSize.width / 2, y: 288),
                                withAttributes: hintAttrs)

        let text = gambleText.isEmpty ? "大" : gambleText
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 90),
            .foregroundColor: UIColor(red: 0xf5 / 255.0, green: 0xc4 / 255.0, blue: 0x51 / 255.0, alpha: 1)
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: CGPoint(x: 240 - size.width / 2, y: 318),
                                withAttributes: attrs)
    }

    private func drawNumber(_ value: Int64, rightEdge: CGFloat, y: CGFloat,
                            minDigits: Int, spacing: CGFloat) {
        guard !digitImages.isEmpty else { return }
        var text = String(max(0, value))
        while text.count < minDigits { text = "0" + text }
        var cursor = rightEdge + 3
        for character in text.reversed() {
            guard let digit = character.wholeNumberValue, digit >= 0, digit < digitImages.count else {
                continue
            }
            cursor -= 20
            digitImages[digit].draw(in: CGRect(x: cursor, y: y, width: 20, height: 34))
            cursor -= spacing
        }
    }

    // MARK: - 触摸

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let raw = touch.location(in: self)
        let point = CGPoint(x: (raw.x - offset.x) / scaleX,
                            y: (raw.y - offset.y) / scaleY)

        if phase == .spinning || phase == .gamble {
            return
        }

        let hasWin = model.win > 0

        // 顶部积分/中奖区、菜单按钮
        if scorePanelRect.contains(point) || winPanelRect.contains(point) || menuRect.contains(point) {
            delegate?.gameViewDidRequestMenu(self)
            return
        }

        // 小 / 大：中奖后押大小，赢了翻倍
        if hasWin, smallRect.contains(point) {
            startGamble(isBig: false)
            return
        }
        if hasWin, bigRect.contains(point) {
            startGamble(isBig: true)
            return
        }

        if startRect.contains(point) {
            if phase == .result || hasWin {
                collect()
            } else {
                startSpin()
            }
            return
        }

        if phase == .result {
            collect()
            return
        }

        for index in 0..<GameView.tiles.count {
            let origin = GameView.tiles[index]
            if CGRect(x: origin.x, y: origin.y, width: 60, height: 57).contains(point) {
                if hasWin {
                    collect()
                } else {
                    let symbol = GameModel.symbols[index]
                    placeBet(group: GameModel.group(for: symbol))
                }
                return
            }
        }

        // 底部筹码区（与安卓 av~aw 命中区一致）
        if point.y > 560, point.y < 660 {
            if hasWin {
                collect()
                return
            }
            var index = GameView.chipHitX.count - 1
            while index >= 0 && point.x < GameView.chipHitX[index] {
                index -= 1
            }
            placeBet(group: 7 - index)
            return
        }
    }

    private func placeBet(group: Int) {
        guard group >= 0, group < 8 else { return }
        if model.addBet(group: group) {
            SoundPlayer.shared.play("in")
            if !model.vibrateDisabled {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            setNeedsDisplay()
        } else if model.score < 1 {
            showToast("点数不足，请在菜单中购买点数")
        } else {
            showToast("该格已满注")
        }
    }

    // MARK: - 押大小

    private func startGamble(isBig: Bool) {
        guard model.win > 0 else {
            showToast("中奖后才能押大小")
            return
        }
        gambleBig = isBig
        gambleText = isBig ? "大" : "小"
        gambleStartTime = CACurrentMediaTime()
        phase = .gamble
        SoundPlayer.shared.play("go")
        setNeedsDisplay()
    }

    private func resolveGamble() {
        let current = model.win
        var chance = 50
        if current > 500 {
            chance = 43
        } else if current > 100 {
            chance = 45
        } else if current < 10 {
            chance = 55
        } else if current < 20 {
            chance = 52
        }

        let success = Int.random(in: 0..<100) < chance

        if success {
            model.setWin(current * 2)
            resultStartTime = CACurrentMediaTime()
            phase = .result
            SoundPlayer.shared.play("win")
            if !model.vibrateDisabled {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            showToast("押\(gambleBig ? "大" : "小")成功，中奖翻倍")
        } else {
            model.setWin(0)
            resultPositions = []
            phase = .idle
            SoundPlayer.shared.play("zha")
            if !model.vibrateDisabled {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            showToast("押\(gambleBig ? "大" : "小")失败，本次中奖清零")
        }
        setNeedsDisplay()
    }

    private func startSpin() {
        guard model.score > 0 else {
            showToast("点数不足，请在菜单中购买点数")
            return
        }
        guard model.totalBet > 0 else {
            showToast("请先在盘面下注")
            return
        }
        guard model.score >= Int64(model.totalBet) else {
            showToast("点数不足，请在菜单中购买点数")
            return
        }
        model.spend(Int64(model.totalBet))

        outcome = model.spin()
        guard let result = outcome else { return }

        spinStartTime = CACurrentMediaTime()
        spinStartIndex = lampIndex
        spinLanding = result.landing
        var steps = 44
        let delta = (result.landing - lampIndex + 24) % 24
        while steps % 24 != delta { steps += 1 }
        spinSteps = steps
        spinDuration = 2.8
        phase = .spinning
        lampBlink = true

        SoundPlayer.shared.play("go")
        SoundPlayer.shared.play("loop", loop: true)
        setNeedsDisplay()
    }

    private func collect() {
        model.collectWin()
        outcome = nil
        resultPositions = []
        phase = .idle
        SoundPlayer.shared.play("open")
        setNeedsDisplay()
    }

    private func showToast(_ text: String) {
        toastLabel.text = text
        toastLabel.alpha = 0
        toastLabel.isHidden = false
        UIView.animate(withDuration: 0.18, animations: {
            self.toastLabel.alpha = 1
        }, completion: { _ in
            UIView.animate(withDuration: 0.25, delay: 1.2, options: [], animations: {
                self.toastLabel.alpha = 0
            }, completion: nil)
        })
    }
}
