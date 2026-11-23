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

    // 中间红色小灯（对应安卓 h(Canvas) 的 ah/ai = 228,306）
    private static let centerLamp = CGPoint(x: 228, y: 306)

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
    private lazy var bannerXiaosy = UIImage(named: "xiaosy.png") ?? UIImage(named: "xiaosy")
    private lazy var bannerXiaosx = UIImage(named: "xiaosx.png") ?? UIImage(named: "xiaosx")
    private lazy var bannerXiaomg = UIImage(named: "xiaomg.png") ?? UIImage(named: "xiaomg")
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

    // 逐格揭示（对应安卓 state 7/8：龙/大奖项落地后，红灯交替闪烁 → 开一格 → 停留 → 再闪）
    private enum RevealStage: Equatable { case none, landing, blink, open }
    private var revealedCount = 0
    private var revealing = false
    private var revealStage: RevealStage = .none
    private var revealStageRemain: CFTimeInterval = 0
    // 一圈红灯交替（安卓 j(Canvas)：每 4 帧奇偶灯互换）
    private var ringPhase = 0
    private var ringTimer: CFTimeInterval = 0

    // 点数不足时的自动补助倒计时（绿色显示在右上角）
    private var autoRemain: TimeInterval = 0

    // 押大小
    private var gambleStartTime: CFTimeInterval = 0
    private var gambleBig = false
    private var gambleText: String = ""

    // 开奖红灯整体闪烁（每 4 帧切换，同安卓 ax）
    private var lampOn = true
    // 押大小：左右竖排红灯交替（0 左 / 1 右）
    private var gambleSide = 0
    private var gambleLampTimer: TimeInterval = 0

    // 长按快速押注
    private var pressedGroup: Int?
    private var rapidTimer: Timer?
    private var rapidActive = false

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

        updateAutoReward(dt)

        switch phase {
        case .idle:
            idleTick += dt
            if idleTick >= 0.24 {
                idleTick = 0
                lampBlink.toggle()
            }
        case .result:
            // 中奖后红灯按节奏闪烁（安卓 ax 每 4 帧取反）
            idleTick += dt
            if idleTick >= 0.13 {
                idleTick = 0
                lampOn.toggle()
            }
            // 一圈红灯交替闪烁（安卓 j(Canvas)：奇偶灯每 4 帧互换）
            if revealStage == .blink {
                ringTimer += dt
                if ringTimer >= 0.067 {
                    ringTimer = 0
                    ringPhase = 1 - ringPhase
                }
            }
            // 龙/大奖项揭示：落地停留 1.8s → 红灯闪烁 1.7s → 开一格 → 停留 1s → 下一格
            if revealing, revealStage != .none {
                revealStageRemain -= dt
                if revealStageRemain <= 0 {
                    switch revealStage {
                    case .landing:
                        if revealedCount >= resultPositions.count {
                            revealing = false
                            revealStage = .none
                            finishReveal()
                        } else {
                            startRevealBlink()
                        }
                    case .blink:
                        revealedCount += 1
                        SoundPlayer.shared.play("zha")
                        revealStage = .open
                        revealStageRemain = 1.0
                    case .open:
                        if revealedCount >= resultPositions.count {
                            revealing = false
                            revealStage = .none
                            finishReveal()
                        } else {
                            startRevealBlink()
                        }
                    case .none:
                        break
                    }
                }
            }
        case .gamble:
            let elapsed = now - gambleStartTime
            // 押大小：左右竖排红灯与大/小文字一起按“先快后慢”交替
            let total = 3.5
            let progress = min(1, elapsed / total)
            let interval = 0.05 + 0.36 * pow(progress, 2.4)
            gambleLampTimer += dt
            if gambleLampTimer >= interval {
                gambleLampTimer = 0
                gambleSide = 1 - gambleSide
                gambleText = (gambleSide == 0) ? "大" : "小"
            }
            if elapsed >= total {
                resolveGamble()
            }
        case .spinning:
            let progress = min(1, (now - spinStartTime) / spinDuration)
            // 慢-快-慢（ease-in-out），与安卓跑灯节奏一致
            let eased: Double
            if progress < 0.5 {
                eased = 2 * progress * progress
            } else {
                eased = 1 - pow(-2 * progress + 2, 2) / 2
            }
            let step = Int(Double(spinSteps) * eased)
            lampIndex = (spinStartIndex + step) % 24
            if progress >= 1 {
                finishSpin(now: now)
            }
        }
        setNeedsDisplay()
    }

    /// 点数低于后台阈值时，按间隔自动补点（右上角绿色倒计时）
    private func updateAutoReward(_ dt: CFTimeInterval) {
        let config = LHJWebViewController.Config.self
        let threshold = Int64(max(1, config.autoThreshold))
        let interval = TimeInterval(max(1, config.autoInterval))
        guard model.score < threshold else {
            autoRemain = 0
            return
        }
        if autoRemain <= 0 {
            autoRemain = interval
        }
        autoRemain -= dt
        if autoRemain <= 0 {
            model.addPoints(Int64(max(1, config.autoReward)))
            autoRemain = interval
        }
    }

    private func finishSpin(now: CFTimeInterval) {
        lampIndex = spinLanding
        lampBlink = true
        lampOn = true
        idleTick = 0

        guard let outcome = outcome else {
            phase = .idle
            return
        }

        // 与安卓一致：无论本次是否押中都显示开奖格
        phase = .result
        resultStartTime = now
        resultPositions = outcome.positions
        revealedCount = 0

        // 龙 / 大三元 / 小三元 / 小四喜 / 大满贯 / 小满贯：
        // 安卓落龙后先停留 1.8s（横幅 + 落点格遮罩），再进入「红灯交替 → 开一格 → 停留」循环
        if outcome.type >= 16 && outcome.type <= 21 {
            SoundPlayer.shared.play("boom")
            revealing = true
            revealStage = .landing
            revealStageRemain = 1.8
            setNeedsDisplay()
            return
        }

        // 普通奖 / 开火车：立即揭示（安卓同帧结算，无逐格动画）
        revealing = false
        revealStage = .none
        revealedCount = resultPositions.count
        finishReveal()
        setNeedsDisplay()
    }

    /// 红灯交替闪烁阶段（安卓 state 8：1.7s 后开下一格）
    private func startRevealBlink() {
        guard revealedCount < resultPositions.count else { return }
        revealStage = .blink
        revealStageRemain = 1.7
        ringPhase = 0
        ringTimer = 0
        // 安卓 t()：开始新一轮闪烁时播 loop
        SoundPlayer.shared.play("loop")
    }

    /// 全部中奖格揭示完成：播 zha + 中奖音效
    private func finishReveal() {
        resultStartTime = CACurrentMediaTime()
        guard let outcome = outcome else { return }
        // 总分等全部格揭示完才显示（与安卓一致：最后跟音效一起出现）
        model.setWin(max(0, outcome.payout))
        // 大奖项每格揭示时已播 zha，这里只处理普通奖
        if revealedCount > 0, outcome.type < 16 {
            SoundPlayer.shared.play("zha")
        }
        // 安卓：中奖格全部揭示完播 bswin（大奖音效）
        if outcome.type >= 16 {
            SoundPlayer.shared.play("bswin")
        }
        if outcome.payout > 0 {
            if !model.vibrateDisabled {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            // 中奖音效：普通奖随机 w1~w7；特殊奖 50% win，否则随机 w1~w7
            let useRandomWin = outcome.type < 14
                || outcome.type == 4 || outcome.type == 6 || outcome.type == 7
            if useRandomWin || Int.random(in: 0..<2) == 1 {
                SoundPlayer.shared.play("w\(Int.random(in: 1...7))")
            } else {
                SoundPlayer.shared.play("win")
            }
        }
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

        // 点数不足：右上角绿色补助倒计时
        let autoThreshold = Int64(max(1, LHJWebViewController.Config.autoThreshold))
        if model.score < autoThreshold && autoRemain > 0 {
            let text = "\(Int(ceil(autoRemain)))s"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 15),
                .foregroundColor: UIColor(red: 0.24, green: 0.95, blue: 0.38, alpha: 1)
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: CGPoint(x: 458 - size.width, y: 71),
                                    withAttributes: attributes)
        }

        // 8 个投注格（中奖后仅中奖那格数字闪烁，其余不闪）
        let winningGroup: Int? = (phase == .result && spinLanding >= 0 && spinLanding < GameModel.symbols.count)
            ? GameModel.group(for: GameModel.symbols[spinLanding]) : nil
        for i in 0..<8 {
            if phase == .result, i == winningGroup, !lampOn { continue }
            drawNumber(Int64(model.bets[i]),
                       rightEdge: GameView.chipX[7 - i],
                       y: 621, minDigits: 2, spacing: 1)
        }

        // 总注
        drawNumber(Int64(model.totalBet), rightEdge: 257, y: 383, minDigits: 2, spacing: 2)

        // 跑灯 / 红灯（含押大小交替、中奖整体闪烁）
        drawLamps()

        // 旋转中：移动格叠加遮罩，与跑灯同一格同步（安卓 c(Canvas, aW)）
        if phase == .spinning {
            // 开火车：整段（3~6 格）遮挡素材一起跟着跑灯移动（安卓每帧重建 C = v, v-1, …）
            if let o = outcome, o.type == 22, o.positions.count > 0 {
                for k in 0..<o.positions.count {
                    let index = ((lampIndex - k) % 24 + 24) % 24
                    guard index >= 0, index < GameView.tiles.count else { continue }
                    let p = GameView.tiles[index]
                    maskImage?.draw(in: CGRect(x: p.x, y: p.y, width: 60, height: 57))
                }
            } else if lampIndex >= 0, lampIndex < GameView.tiles.count {
                let p = GameView.tiles[lampIndex]
                maskImage?.draw(in: CGRect(x: p.x, y: p.y, width: 60, height: 57))
            }
        }

        // 中奖高亮（只画已经揭示的格）+ 落点格遮罩 + 大奖项横幅
        if phase == .result {
            let shown = min(revealedCount, resultPositions.count)
            for i in 0..<shown {
                let index = resultPositions[i]
                guard index >= 0, index < GameView.tiles.count else { continue }
                let p = GameView.tiles[index]
                maskImage?.draw(in: CGRect(x: p.x, y: p.y, width: 60, height: 57))
            }
            // 落龙停留：落点格遮罩（安卓 k(Canvas) 的 c(Canvas, aW)）
            if revealStage == .landing, lampIndex >= 0, lampIndex < GameView.tiles.count {
                let p = GameView.tiles[lampIndex]
                maskImage?.draw(in: CGRect(x: p.x, y: p.y, width: 60, height: 57))
            }
            // 大奖项横幅：等中奖格全部揭示完才弹（和开火车开奖节奏一致）
            if !revealing {
                drawBanner(now: CACurrentMediaTime())
            }
        }

        ctx.restoreGState()
    }

    /// 跑灯 / 红灯（对应安卓 c(Canvas) / e(Canvas) 各阶段绘制）
    private func drawLamps() {
        guard let lamp = lampImage else { return }
        func draw(_ i: Int) {
            guard i >= 0, i < GameView.lamps.count else { return }
            let p = GameView.lamps[i]
            lamp.draw(in: CGRect(x: p.x, y: p.y, width: 24, height: 24))
        }
        // 左侧竖排（含左上/左下角），同安卓 18..23 + 0
        let leftBand = [0, 18, 19, 20, 21, 22, 23]
        // 右侧竖排（含右上/右下角），同安卓 6..12
        let rightBand = [6, 7, 8, 9, 10, 11, 12]

        switch phase {
        case .gamble:
            // 押大小：左右竖排红灯交替亮，不点亮上下排
            for i in (gambleSide == 0 ? leftBand : rightBand) { draw(i) }
        case .result:
            if revealStage == .blink {
                // 一圈红灯奇偶交替（安卓 j(Canvas)：每 4 帧奇偶互换）
                for i in 0..<GameView.lamps.count where i % 2 == ringPhase {
                    draw(i)
                }
            } else if lampOn {
                // 落龙停留 / 开格停留：中间红灯 + 当前格跑灯一起闪
                lamp.draw(in: CGRect(x: GameView.centerLamp.x, y: GameView.centerLamp.y, width: 24, height: 24))
                draw(lampIndex)
            }
        case .spinning:
            // 跑灯：只亮当前移动格对应的那颗灯
            draw(lampIndex)
        default:
            // 空闲：单灯缓慢闪烁
            if lampBlink { draw(lampIndex) }
        }
    }

    /// 龙(16)落地后的实际开奖格决定该显示哪种大奖横幅（如 4 个苹果 = 小四喜）
    private var bannerType: Int {
        guard let o = outcome else { return -1 }
        if o.type != 16 { return o.type }
        let syms = resultPositions.map { GameModel.symbols[$0] }
        let set = Set(syms)
        if syms.count == 4 && set == [0] { return 19 }                       // 小四喜：4 个零
        if syms.count == 3 && set == [4, 5, 6] { return 17 }                 // 大三元
        if syms.count == 3 && set == [1, 2, 3] { return 18 }                 // 小三元
        if syms.count == 8 && set == Set(0...7) { return 20 }                // 大满贯
        if syms.count == 8 && set == Set([0, 14] + Array(8...13)) { return 21 } // 小满贯
        return -1
    }

    private func drawBanner(now: CFTimeInterval) {
        guard outcome != nil else { return }
        let image: UIImage?
        switch bannerType {
        case 17: image = bannerDasy
        case 18: image = bannerXiaosy
        case 19: image = bannerXiaosx
        case 20: image = bannerDamg
        case 21: image = bannerXiaomg
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

    /// 计算某个设计坐标点对应的下注组（盘面格或底部筹码区），未命中返回 nil
    private func betGroup(at point: CGPoint) -> Int? {
        if phase == .spinning || phase == .gamble || model.win > 0 { return nil }
        for index in 0..<GameView.tiles.count {
            let origin = GameView.tiles[index]
            if CGRect(x: origin.x, y: origin.y, width: 60, height: 57).contains(point) {
                return GameModel.group(for: GameModel.symbols[index])
            }
        }
        if point.y > 560, point.y < 660 {
            var index = GameView.chipHitX.count - 1
            while index >= 0 && point.x < GameView.chipHitX[index] {
                index -= 1
            }
            return 7 - index
        }
        return nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let raw = touch.location(in: self)
        let point = CGPoint(x: (raw.x - offset.x) / scaleX,
                            y: (raw.y - offset.y) / scaleY)
        guard let group = betGroup(at: point) else { return }
        pressedGroup = group
        rapidActive = false
        rapidTimer?.invalidate()
        let delayTimer = Timer(timeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.scheduleRapidBet()
        }
        rapidTimer = delayTimer
        RunLoop.main.add(delayTimer, forMode: .common)
    }

    /// 长按延时结束后开始连续快速押注
    private func scheduleRapidBet() {
        guard let g = pressedGroup else { return }
        rapidActive = true
        rapidTimer?.invalidate()
        let timer = Timer(timeInterval: 0.13, repeats: true) { [weak self] _ in
            self?.placeBet(group: g)
        }
        rapidTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        placeBet(group: g)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        rapidTimer?.invalidate()
        rapidTimer = nil
        pressedGroup = nil
        rapidActive = false
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let raw = touch.location(in: self)
        let point = CGPoint(x: (raw.x - offset.x) / scaleX,
                            y: (raw.y - offset.y) / scaleY)

        rapidTimer?.invalidate()
        rapidTimer = nil
        pressedGroup = nil
        let wasRapid = rapidActive
        rapidActive = false

        if phase == .spinning || phase == .gamble {
            return
        }

        // 逐格揭示 / 二次开奖期间不接受点击，避免跳过开奖动画
        if phase == .result && revealing {
            return
        }

        // 长按快速押注期间释放手指，不再触发单次押注
        if wasRapid {
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
            // 8 个下注格分别对应安卓 s1~s8
            SoundPlayer.shared.play("s\(group + 1)")
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
        revealing = false
        revealStage = .none
        revealStageRemain = 0
        ringPhase = 0
        ringTimer = 0
        gambleSide = 0
        gambleLampTimer = 0
        // 立即停止中奖音乐（安卓 j() 播放前先 z() 停掉上一段）
        SoundPlayer.shared.stopAll()
        // 安卓押大小固定播放 bs
        SoundPlayer.shared.play("bs")
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
            lampOn = true
            idleTick = 0
            revealedCount = resultPositions.count
            revealing = false
            revealStage = .none
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
        // 上一局中奖未收分时先入账（安卓点击开始时 addHoldAndSave）
        if model.win > 0 {
            model.collectWin()
        }
        switch model.tryStart() {
        case .noScore, .insufficient:
            model.clearBets()
            showToast("点数不足，请在菜单中购买点数")
            return
        case .noBet:
            model.clearBets()
            showToast("请先在盘面下注")
            return
        case .ok:
            break
        }

        model.commitSpin()
        outcome = model.spin(currentLamp: lampIndex)
        guard let result = outcome else { return }

        spinStartTime = CACurrentMediaTime()
        spinStartIndex = lampIndex
        spinLanding = result.landing
        var steps = 44
        let delta = (result.landing - lampIndex + 24) % 24
        while steps % 24 != delta { steps += 1 }
        spinSteps = steps
        spinDuration = 5.4
        phase = .spinning
        lampBlink = true

        // 立即停止上一段中奖音乐（安卓 j() 播放前先 z() 停掉上一段）
        SoundPlayer.shared.stopAll()
        // 开火车（type 22 中大奖）播放 train，其余播放 go（安卓 r() 固定单次播放）
        if result.type == 22 {
            SoundPlayer.shared.play("train")
        } else {
            SoundPlayer.shared.play("go")
        }
        setNeedsDisplay()
    }

    private func collect() {
        model.collectWin()
        outcome = nil
        resultPositions = []
        revealedCount = 0
        revealing = false
        revealStage = .none
        revealStageRemain = 0
        ringPhase = 0
        ringTimer = 0
        phase = .idle
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
