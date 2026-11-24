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
    // 龙大奖(16)触发概率（后台可调，默认 20）
    static var dragonRate = 20
    // 龙中 0~11 格的权重（后台可调）
    static var dragonWeights = [20, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7]
    // 小满贯 / 小三元 / 小四喜 强制触发概率（后台可调，默认 0 保持原版）
    static var xiaoManGuanRate = 0
    static var xiaoSanYuanRate = 0
    static var sixiRate = 0

    private let defaults: UserDefaults
    private let saveURL: URL

    private(set) var score: Int64 = 10
    private(set) var win: Int64 = 0
    private(set) var topScore: Int64 = 0
    private(set) var bets = [Int](repeating: 0, count: 8)
    /// 上一局已提交的押注方案（对应安卓 Q，用于“点开始复押上一局”）
    private(set) var lastBets = [Int](repeating: 0, count: 8)
    /// 本局是否已下过注（对应安卓 ay；开奖后复位，首次下注时先清空旧注）
    private(set) var betPlaced = false
    private(set) var pool: Int32 = 0
    private(set) var totalSpins: Int64 = 0
    private(set) var maxWinScore: Int64 = 0
    private(set) var maxGambleWinScore: Int64 = 0
    private(set) var maxGambleWinStreak: Int64 = 0
    private var gambleWinStreak: Int64 = 0
    private var pendingWin: Int64?

    private struct SaveState: Codable {
        let version: Int
        let score: Int64
        let topScore: Int64
        let win: Int64
        let pool: Int32
        let openBets: [Int]?
        let pendingWin: Int64?
        let totalSpins: Int64
        let maxWinScore: Int64
        let maxGambleWinScore: Int64
        let maxGambleWinStreak: Int64
    }

    private struct SaveEnvelope: Codable {
        let payload: Data
        let checksum: String
    }

    var soundDisabled: Bool {
        didSet { defaults.set(soundDisabled, forKey: "disSnd") }
    }
    var vibrateDisabled: Bool {
        didSet { defaults.set(vibrateDisabled, forKey: "disVib") }
    }

    init(defaults: UserDefaults = .standard, saveURL: URL? = nil) {
        self.defaults = defaults
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        self.saveURL = saveURL ?? support.appendingPathComponent("LHJ").appendingPathComponent("GameState-v1.plist")
        soundDisabled = defaults.bool(forKey: "disSnd")
        vibrateDisabled = defaults.bool(forKey: "disVib")
        if let state = Self.readSave(at: self.saveURL) {
            score = state.score
            topScore = state.topScore
            win = state.pendingWin ?? state.win
            pool = state.pool
            totalSpins = state.totalSpins
            maxWinScore = state.maxWinScore
            maxGambleWinScore = state.maxGambleWinScore
            maxGambleWinStreak = state.maxGambleWinStreak
            if let openBets = state.openBets {
                bets = openBets
                betPlaced = true
            }
            // 动画中退出时恢复已确定的结果，不重复扣费或派奖。
            if state.pendingWin != nil { save() }
        } else if !FileManager.default.fileExists(atPath: self.saveURL.path) {
            // 旧 iOS 将三个点数字段存为 Double；迁移保留原有数据。
            score = Self.legacyPoints(defaults, key: "curScore") ?? 10
            topScore = Self.legacyPoints(defaults, key: "topScore") ?? 0
            win = Self.legacyPoints(defaults, key: "win") ?? 0
            maxWinScore = win
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

    /// 单击 1 点；长按每次最多 3 点，受余额和单组 99 点上限约束。
    @discardableResult
    func addBet(group: Int, count: Int = 1) -> Int {
        guard pendingWin == nil, bets.indices.contains(group), count > 0,
              score > 0 || win > 0 else { return 0 }
        // 安卓先清旧注再检查上限，否则上一局押满 99 会挡住同组新下注。
        if !betPlaced {
            bets = [Int](repeating: 0, count: bets.count)
        }
        let room = min(count, 99 - bets[group])
        guard room > 0 else { return 0 }
        moveWinToScore()
        let placed = Int(min(Int64(room), score))
        guard placed > 0 else { return 0 }
        betPlaced = true
        score -= Int64(placed)
        bets[group] += placed
        save()
        return placed
    }

    // MARK: - 结算

    func collectWin() {
        guard pendingWin == nil, win > 0 else { return }
        moveWinToScore()
        if !betPlaced { bets = [Int](repeating: 0, count: bets.count) }
        save()
    }

    func addPoints(_ value: Int64) {
        guard value > 0 else { return }
        score = Self.sum(score, value)
        topScore = max(topScore, score)
        save()
    }

    private func moveWinToScore() {
        guard win > 0 else { return }
        score = Self.sum(score, win)
        topScore = max(topScore, score)
        win = 0
        gambleWinStreak = 0
    }

    private static func sum(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : value
    }

    enum StartResult {
        case started(Outcome)
        case noScore, noBet, insufficient, busy
    }

    func beginSpin(currentLamp: Int) -> StartResult {
        guard pendingWin == nil, win == 0 else { return .busy }
        if !betPlaced {
            let total = Int64(lastBets.reduce(0, +))
            guard score > 0 else { return .noScore }
            guard total > 0 else { return .noBet }
            guard score >= total else { return .insufficient }
            bets = lastBets
            score -= total
        }
        lastBets = bets
        betPlaced = false
        gambleWinStreak = 0
        totalSpins = Self.sum(totalSpins, 1)
        let outcome = spin(currentLamp: currentLamp)
        pendingWin = outcome.payout
        maxWinScore = max(maxWinScore, outcome.payout)
        save()
        return .started(outcome)
    }

    static func gambleChance(for win: Int64) -> Int {
        // 安卓先判断 <20；后面的 <10 分支实际不可达。
        if win > 500 { return 43 }
        if win > 100 { return 45 }
        if win < 20 { return 52 }
        return 50
    }

    struct GambleOutcome {
        let won: Bool
        let number: Int
    }

    func beginGamble(isBig: Bool, roll: Int = Int.random(in: 0..<100),
                     face: Int = Int.random(in: 1...6)) -> GambleOutcome? {
        guard win > 0, pendingWin == nil else { return nil }
        let won = roll < Self.gambleChance(for: win)
        let number = (won == isBig) ? face + 7 : face
        let payout = won ? Self.sum(win, win) : 0
        pendingWin = payout
        if won {
            gambleWinStreak = Self.sum(gambleWinStreak, 1)
            maxGambleWinStreak = max(maxGambleWinStreak, gambleWinStreak)
            maxGambleWinScore = max(maxGambleWinScore, payout)
            maxWinScore = max(maxWinScore, payout)
        } else {
            gambleWinStreak = 0
        }
        save()
        return GambleOutcome(won: won, number: number)
    }

    func finishRoundAnimation() {
        guard let payout = pendingWin else { return }
        win = payout
        pendingWin = nil
        save()
    }

    private static func legacyPoints(_ defaults: UserDefaults, key: String) -> Int64? {
        guard let number = defaults.object(forKey: key) as? NSNumber else { return nil }
        if let integer = Int64(number.stringValue) { return max(0, integer) }
        let value = number.doubleValue
        guard value.isFinite, value >= 0 else { return 0 }
        return value >= Double(Int64.max) ? Int64.max : Int64(value)
    }

    /// 本地完整性检测，不作为服务器或跨设备授权凭据。
    private static func checksum(_ data: Data) -> String {
        let value = data.reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
        return String(value, radix: 16)
    }

    private static func readSave(at url: URL) -> SaveState? {
        guard let data = try? Data(contentsOf: url),
              let envelope = try? PropertyListDecoder().decode(SaveEnvelope.self, from: data),
              envelope.checksum == checksum(envelope.payload),
              let state = try? PropertyListDecoder().decode(SaveState.self, from: envelope.payload),
              (1...2).contains(state.version),
              state.score >= 0, state.topScore >= 0, state.win >= 0,
              (state.pendingWin ?? 0) >= 0 else { return nil }
        if let bets = state.openBets {
            guard state.pendingWin == nil, state.win == 0, bets.count == 8,
                  bets.allSatisfy({ (0...99).contains($0) }), bets.contains(where: { $0 > 0 }) else { return nil }
        }
        return state
    }

    private func save() {
        let state = SaveState(version: 1, score: score, topScore: topScore, win: win, pool: pool,
                              openBets: betPlaced ? bets : nil, pendingWin: pendingWin, totalSpins: totalSpins,
                              maxWinScore: maxWinScore, maxGambleWinScore: maxGambleWinScore,
                              maxGambleWinStreak: maxGambleWinStreak)
        do {
            let encoder = PropertyListEncoder()
            let payload = try encoder.encode(state)
            let data = try encoder.encode(SaveEnvelope(payload: payload, checksum: Self.checksum(payload)))
            try FileManager.default.createDirectory(at: saveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            NSLog("LHJ game state save failed: %@", error.localizedDescription)
        }
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

    /// 从当前灯位置顺时针找下一条龙（symbol 16），与安卓 r() 一致
    static func nextDragon(after start: Int) -> Int {
        for offset in 1...24 {
            let idx = (start + offset) % 24
            if GameModel.symbols[idx] == 16 { return idx }
        }
        return 9
    }

    /// 大奖命中后按权重挑一个类型；返回 -1 表示无可用候选（回退普通随机）
    private func pickBigPrize(totalKind: Int, outs: [Int], w22: Int) -> Int {
        let candidates: [(code: Int, weight: Int)] = [
            (20, totalKind >= 4 && outs[20] > 0 ? 100 : 0),        // 大满贯
            (17, totalKind >= 2 && outs[17] > 0 ? 100 : 0),        // 大三元
            (22, outs[22] > 0 && w22 > 3 ? 100 : 0),               // 开火车
            (21, outs[21] > 0 ? GameModel.xiaoManGuanRate : 0),    // 小满贯
            (18, outs[18] > 0 ? GameModel.xiaoSanYuanRate : 0),    // 小三元
            (19, outs[19] > 0 ? GameModel.sixiRate : 0)            // 小四喜
        ]
        let totalWeight = candidates.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return -1 }
        var roll = Int.random(in: 0..<totalWeight)
        for item in candidates {
            roll -= item.weight
            if roll < 0 { return item.code }
        }
        return -1
    }

    private func spin(currentLamp: Int) -> Outcome {
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
        // 安卓 s_p 使用有符号 32 位整数，单位为 1/100 点。
        pool = pool &+ Int32(GameModel.poolRatio[level] * total)
        let target = Int(pool / 100)

        // 2. 计算 23 种中奖组合的金额
        var outs = [Int](repeating: 0, count: 23)
        for i in 0..<16 { outs[i] = betAmount(for: i) }

        // 16：龙 —— 按后台权重抽 0~11 格（权重和无效时退回 1~11 均匀 + 20% 空龙）
        var w16 = 0
        let weights = GameModel.dragonWeights
        let weightSum = weights.reduce(0, +)
        if weightSum > 0 {
            var roll = Int.random(in: 0..<weightSum)
            for (k, weight) in weights.enumerated() {
                roll -= weight
                if roll < 0 { w16 = k; break }
            }
        } else {
            w16 = Int.random(in: 0..<11) + 1
            if Int.random(in: 0..<100) < 20 { w16 = 0 }
        }
        var pos16: [Int] = []
        var sum16 = 0
        var guard16 = 0
        while pos16.count < w16 && guard16 < 500 {
            guard16 += 1
            let p = Int.random(in: 0..<24)
            if GameModel.symbols[p] == 16 { continue }
            if pos16.contains(p) { continue }
            // 只抽有押注的格，保证「亮灯格数 == 实际派奖格数」
            if betAmount(for: GameModel.symbols[p]) <= 0 { continue }
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

        // 3. 特殊大奖优先：龙按 dragonRate 独立判定；其余大奖先按 winRate 判定一次，命中后按权重选类型
        var type = -1
        if total > 0 {
            if Int.random(in: 0..<100) < GameModel.dragonRate {
                type = 16   // 龙
            } else if Int.random(in: 0..<100) < GameModel.winRate {
                type = pickBigPrize(totalKind: totalKind, outs: outs, w22: w22)
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
        pool = pool &- Int32(100 * outs[type])

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

        // 跑灯落点：龙/大三元/小三元/小四喜/大满贯/小满贯都落到下一条龙（二次触发），开火车落到火车起点
        let landing: Int
        switch type {
        case 16...21:
            landing = GameModel.nextDragon(after: currentLamp)
        case 22:
            landing = v22
        default:
            landing = positions.first ?? Int.random(in: 0..<24)
        }

        return Outcome(type: type, positions: positions, payout: payout,
                       landing: landing, landingSymbol: GameModel.symbols[landing])
    }
}
