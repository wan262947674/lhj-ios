import Foundation

/// 与安卓版一致的核心数据与开奖逻辑
final class GameModel {

    static let shared = GameModel()

    // 盘面 24 格对应的符号（索引与 GameBody.e 完全一致）
    static let symbols: [Int] = [
        1, 3, 15, 7, 14, 0, 2, 4, 11, 16, 0, 8,
        1, 3, 13, 6, 0, 9, 2, 5, 12, 16, 0, 10
    ]
    // 符号倍率（GameBody.j）
    static let mult: [Int] = [5, 10, 15, 20, 20, 30, 40, 100, 2, 2, 2, 2, 2, 2, 25, 50]
    // 出奖档位权重（GameBody.a）
    static let buckets: [Int] = [838, 139, 20, 2, 1]
    // 档位返奖系数（GameBody.b），按 1/100 点计
    static let poolRatio: [Int] = [25, 100, 1000, 10000, 22000]
    // 特殊奖触发概率（LhjConfig.winRate，后台可调，默认 20）
    static var winRate = 20

    private let defaults = UserDefaults.standard

    private(set) var score: Int64 = 10
    private(set) var win: Int64 = 0
    private(set) var topScore: Int64 = 0
    private(set) var bets = [Int](repeating: 0, count: 8)
    /// 上一局已提交的押注方案（对应安卓 Q，用于“点开始复押上一局”）
    private(set) var lastBets = [Int](repeating: 0, count: 8)
    /// 本局是否已下过注（对应安卓 ay；开奖后复位，首次下注时先清空旧注）
    private(set) var betPlaced = false
    private var pool: Int64 = 0

    var soundDisabled: Bool {
        didSet { defaults.set(soundDisabled, forKey: "disSnd") }
    }
    var vibrateDisabled: Bool {
        didSet { defaults.set(vibrateDisabled, forKey: "disVib") }
    }

    private init() {
        soundDisabled = defaults.bool(forKey: "disSnd")
        vibrateDisabled = defaults.bool(forKey: "disVib")
        if defaults.object(forKey: "curScore") != nil {
            score = Int64(defaults.double(forKey: "curScore"))
            topScore = Int64(defaults.double(forKey: "topScore"))
            win = Int64(defaults.double(forKey: "win"))
            if score < 0 { score = 0 }
        } else {
            score = 10
            save()
        }
    }

    // MARK: - 下注

    static func group(for symbol: Int) -> Int {
        if symbol < 8 { return symbol }
        if symbol == 15 { return 7 }
        return symbol - 7
    }

    func betAmount(for symbol: Int) -> Int {
        if symbol == 16 { return 0 }
        let g = GameModel.group(for: symbol)
        guard g >= 0, g < bets.count else { return 0 }
        return bets[g] * GameModel.mult[symbol]
    }

    var totalBet: Int { bets.reduce(0, +) }
    var betKinds: Int { bets.filter { $0 > 0 }.count }

    @discardableResult
    func addBet(group: Int) -> Bool {
        guard group >= 0, group < bets.count else { return false }
        guard bets[group] < 99 else { return false }
        guard score >= 1 else { return false }
        // 本局第一次下注前，清空上一局遗留的押注（安卓 d(I)）
        if !betPlaced {
            betPlaced = true
            bets = [Int](repeating: 0, count: bets.count)
        }
        score -= 1
        bets[group] += 1
        save()
        return true
    }

    func clearBets() {
        bets = [Int](repeating: 0, count: 8)
        save()
    }

    // MARK: - 结算

    func setWin(_ value: Int64) {
        win = max(0, value)
        save()
    }

    func collectWin() {
        guard win > 0 else { return }
        score += win
        if score > topScore { topScore = score }
        win = 0
        save()
    }

    func addPoints(_ value: Int64) {
        guard value > 0 else { return }
        score += value
        if score > topScore { topScore = score }
        save()
    }

    enum StartCheck {
        case ok
        case noScore       // 余额为 0
        case noBet         // 上一局没有押注
        case insufficient  // 余额不足
    }

    /// 点击开始时的校验/复押逻辑（对应安卓 onTouch 中 ay==false 的复押分支）
    func tryStart() -> StartCheck {
        if betPlaced {
            // 本局已下注，点数在下注时已扣
            return .ok
        }
        // 复押上一局方案
        let total = lastBets.reduce(0, +)
        if score == 0 { return .noScore }
        if total <= 0 { return .noBet }
        if score < Int64(total) { return .insufficient }
        bets = lastBets
        score -= Int64(total)
        save()
        return .ok
    }

    /// 开奖前提交本局押注（对应安卓 r()：保存上一局方案并复位 ay）
    func commitSpin() {
        lastBets = bets
        betPlaced = false
        save()
    }

    private func save() {
        defaults.set(Double(score), forKey: "curScore")
        defaults.set(Double(topScore), forKey: "topScore")
        defaults.set(Double(win), forKey: "win")
    }

    // MARK: - 开奖

    struct Outcome {
        let type: Int          // u
        let positions: [Int]   // 中奖格
        let payout: Int64
        let landing: Int       // 跑灯停下的格
        let landingSymbol: Int // 停下那格的图案
    }

    private func randomPosition(of symbol: Int) -> [Int] {
        let candidates = GameModel.symbols.enumerated().compactMap { $0.element == symbol ? $0.offset : nil }
        guard let p = candidates.randomElement() else { return [] }
        return [p]
    }

    func spin() -> Outcome {
        let total = totalBet
        let totalKind = betKinds

        // 1. 按权重选出档位
        let r = Int.random(in: 0..<1000)
        var level = 0
        var acc = 0
        for i in 0..<GameModel.buckets.count {
            acc += GameModel.buckets[i]
            if r < acc { level = i; break }
        }
        pool += Int64(GameModel.poolRatio[level] * total)
        let target = Int(clamping: pool / 100)

        // 2. 计算 23 种中奖组合的金额
        var outs = [Int](repeating: 0, count: 23)
        for i in 0..<16 { outs[i] = betAmount(for: i) }

        // 16：龙 —— 5~11 个不同格（20% 概率 0 格）
        var w16 = Int.random(in: 0..<7) + 5
        if Int.random(in: 0..<100) < 20 { w16 = 0 }
        var pos16: [Int] = []
        var sum16 = 0
        var guard16 = 0
        while pos16.count < w16 && guard16 < 500 {
            guard16 += 1
            let p = Int.random(in: 0..<24)
            if GameModel.symbols[p] == 16 { continue }
            if pos16.contains(p) { continue }
            pos16.append(p)
            sum16 += betAmount(for: GameModel.symbols[p])
        }
        outs[16] = sum16

        // 17：大三元（符号 4/5/6）
        outs[17] = betAmount(for: 4) + betAmount(for: 5) + betAmount(for: 6)
        // 18：小三元（符号 1/2/3）
        outs[18] = betAmount(for: 1) + betAmount(for: 2) + betAmount(for: 3)
        // 19：小四喜（符号 0 × 4）
        outs[19] = betAmount(for: 0) * 4
        // 20：大满贯（8 组全中）
        var sum20 = 0
        for g in 0..<8 { sum20 += bets[g] * GameModel.mult[g] }
        outs[20] = sum20
        // 21：小满贯
        outs[21] = bets[0] * GameModel.mult[0] + bets[7] * GameModel.mult[14] + (1...6).reduce(0) { $0 + bets[$1] * 2 }

        // 22：开火车 —— 随机连续 3~6 格
        let w22 = Int.random(in: 0..<4) + 3
        let v22 = Int.random(in: 0..<24)
        var pos22: [Int] = []
        var sum22 = 0
        for k in 0..<w22 {
            let p = ((v22 - k) % 24 + 24) % 24
            pos22.append(p)
            sum22 += betAmount(for: GameModel.symbols[p])
        }
        outs[22] = sum22

        // 3. 特殊情况优先（与 GameBody.cal 一致：大三元奖池可负担且超过总注 10 倍）
        var type = -1
        if total > 0 {
            let bigRatio = outs[20] / total
            if Int.random(in: 0..<100) < GameModel.winRate,
               outs[20] <= target, bigRatio > 10, totalKind >= 4 {
                type = 20
            } else if Int.random(in: 0..<100) < GameModel.winRate,
                      outs[17] <= target, bigRatio > 10, totalKind >= 2 {
                type = 17
            } else if Int.random(in: 0..<100) < GameModel.winRate,
                      outs[22] <= target, bigRatio > 10, w22 > 3 {
                type = 22
            }
        }

        // 4. 按“返奖池”阈值随机挑一个组合
        let minOut = outs.min() ?? 0
        let threshold = max(target, minOut)
        if type < 0 {
            var tries = 0
            repeat {
                type = Int.random(in: 0..<23)
                tries += 1
            } while outs[type] > threshold && tries < 300
        }
        pool -= Int64(100 * outs[type])

        // 5. 生成中奖格
        var positions: [Int] = []
        switch type {
        case 0...15:
            positions = randomPosition(of: type)
        case 16:
            positions = pos16
        case 17:
            positions = randomPosition(of: 4) + randomPosition(of: 5) + randomPosition(of: 6)
        case 18:
            positions = randomPosition(of: 1) + randomPosition(of: 2) + randomPosition(of: 3)
        case 19:
            // 小四喜：4 格全是符号 0
            positions = GameModel.symbols.enumerated().compactMap { $0.element == 0 ? $0.offset : nil }
        case 20:
            // 大满贯：8 格（符号 0~7 各一格）
            for g in 0..<8 {
                positions += randomPosition(of: g)
            }
        case 21:
            // 小满贯：符号 0、14 及 8~13 各一格
            positions = randomPosition(of: 0) + randomPosition(of: 14)
            for s in 8..<14 {
                positions += randomPosition(of: s)
            }
        default:
            positions = pos22
        }

        var payout: Int64 = 0
        for p in positions {
            payout += Int64(betAmount(for: GameModel.symbols[p]))
        }

        let landing = positions.first ?? Int.random(in: 0..<24)

        return Outcome(type: type, positions: positions, payout: payout,
                       landing: landing, landingSymbol: GameModel.symbols[landing])
    }
}
