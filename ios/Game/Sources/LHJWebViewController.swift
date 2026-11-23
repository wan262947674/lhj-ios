import UIKit
import WebKit
import CryptoKit

/// 排行榜 / 成就 / 观看广告 / 积分兑换 / 购买卡密 的通用联网页（对接 8080 后台）
final class LHJWebViewController: UIViewController, UITextFieldDelegate {

    enum Action: String {
        case rank
        case ach
        case exchange
        case ad
        case buy
    }

    /// 后台下发/缓存的运营配置
    struct Config {
        static var adURL = ""
        static var buyURL = ""
        static var adReward = 100
        static var adCooldown = 60
        static var autoEnabled = true
        static var autoThreshold = 500
        static var autoReward = 50
        static var autoInterval = 60
        static var helpText = ""
        static var moreURL = ""
        static var winRate = 20
        static var dragonRate = 20
    }

    /// 玩家当前积分（后台 points）
    static private(set) var playerPoints: Int64 = 0

    private enum Mode {
        case display
        case config
        case points
    }

    /// 后台地址（Base64，界面不展示）
    private static let serverBase64 = "aHR0cDovLzEuMTE3LjIwNC4xMzc6ODA4MA=="

    /// 请求/回包签名密钥（与安卓 LhjSign 一致）
    static let signSecret = "LHJ@2026#sign"

    static func md5(_ text: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 补全 http 协议，避免 WKWebView 白屏（后台地址可能填成 www.xxx.com）
    static func normalizedURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            text = "http://" + text
        }
        if let url = URL(string: text) { return url }
        if let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) {
            return URL(string: encoded)
        }
        return nil
    }

    private let action: Action
    private let titleLabel = UILabel()
    private let contentView = UITextView()
    private let inputField = UITextField()
    private let actionButton = UIButton(type: .system)
    private let watchButton = UIButton(type: .system)
    private let claimButton = UIButton(type: .system)
    private let signButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private var adWatched = false

    init(action: Action) {
        self.action = action
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var prefersStatusBarHidden: Bool { true }

    private var screenTitle: String {
        switch action {
        case .rank: return "高手排行榜"
        case .ach: return "成就列表"
        case .exchange: return "积分兑换点数"
        case .ad: return "免费获取积分"
        case .buy: return "购买卡密"
        }
    }

    private var baseURLString: String? {
        guard let data = Data(base64Encoded: LHJWebViewController.serverBase64),
              let base = String(data: data, encoding: .utf8) else { return nil }
        return base
    }

    private var deviceID: String {
        return UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0x11 / 255.0, green: 0x11 / 255.0,
                                      blue: 0x11 / 255.0, alpha: 1)
        buildUI()
        switch action {
        case .rank, .ach:
            send(action.rawValue, mode: .display)
        case .exchange:
            contentView.text = "输入要兑换的积分数量（1 积分 = 1 游戏点数）"
        case .ad:
            contentView.text = "正在读取配置..."
            send("config", mode: .config)
        case .buy:
            contentView.text = "正在打开购买页面..."
            send("config", mode: .config)
        }
    }

    private func buildUI() {
        titleLabel.text = screenTitle
        titleLabel.textColor = UIColor(red: 0xf5 / 255.0, green: 0xc4 / 255.0, blue: 0x51 / 255.0, alpha: 1)
        titleLabel.font = UIFont.boldSystemFont(ofSize: 22)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        contentView.backgroundColor = .clear
        contentView.textColor = .white
        contentView.font = UIFont.systemFont(ofSize: 16)
        contentView.isEditable = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)

        inputField.isHidden = action != .exchange
        inputField.keyboardType = .numberPad
        inputField.textColor = .white
        inputField.attributedPlaceholder = NSAttributedString(
            string: "输入要兑换的积分数量",
            attributes: [.foregroundColor: UIColor(white: 0.55, alpha: 1)]
        )
        inputField.backgroundColor = UIColor(red: 0x22 / 255.0, green: 0x28 / 255.0,
                                            blue: 0x33 / 255.0, alpha: 1)
        inputField.layer.cornerRadius = 6
        inputField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        inputField.leftViewMode = .always
        inputField.delegate = self
        inputField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputField)

        actionButton.isHidden = action != .exchange
        actionButton.setTitle("立即兑换", for: .normal)
        actionButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 17)
        actionButton.setTitleColor(.black, for: .normal)
        actionButton.backgroundColor = UIColor(red: 0xf5 / 255.0, green: 0xc4 / 255.0,
                                              blue: 0x51 / 255.0, alpha: 1)
        actionButton.layer.cornerRadius = 6
        actionButton.addTarget(self, action: #selector(exchangeTapped), for: .touchUpInside)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(actionButton)

        watchButton.isHidden = action != .ad
        watchButton.setTitle("观看广告", for: .normal)
        watchButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 17)
        watchButton.setTitleColor(.black, for: .normal)
        watchButton.backgroundColor = UIColor(red: 0xf5 / 255.0, green: 0xc4 / 255.0,
                                             blue: 0x51 / 255.0, alpha: 1)
        watchButton.layer.cornerRadius = 6
        watchButton.addTarget(self, action: #selector(watchTapped), for: .touchUpInside)
        watchButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(watchButton)

        claimButton.isHidden = action != .ad
        claimButton.isEnabled = action != .ad
        claimButton.setTitle("领取奖励", for: .normal)
        claimButton.titleLabel?.font = UIFont.systemFont(ofSize: 17)
        claimButton.setTitleColor(UIColor(red: 0xe9 / 255.0, green: 0xdc / 255.0,
                                         blue: 0xc0 / 255.0, alpha: 1), for: .normal)
        claimButton.backgroundColor = UIColor(red: 0x22 / 255.0, green: 0x28 / 255.0,
                                             blue: 0x33 / 255.0, alpha: 1)
        claimButton.layer.cornerRadius = 6
        claimButton.addTarget(self, action: #selector(claimTapped), for: .touchUpInside)
        claimButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(claimButton)

        signButton.isHidden = action != .ad
        signButton.setTitle("每日签到", for: .normal)
        signButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        signButton.setTitleColor(UIColor(red: 0xe9 / 255.0, green: 0xdc / 255.0,
                                         blue: 0xb0 / 255.0, alpha: 1), for: .normal)
        signButton.backgroundColor = UIColor(red: 0x22 / 255.0, green: 0x28 / 255.0,
                                             blue: 0x33 / 255.0, alpha: 1)
        signButton.layer.cornerRadius = 6
        signButton.addTarget(self, action: #selector(signTapped), for: .touchUpInside)
        signButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(signButton)

        closeButton.setTitle("关闭", for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 17)
        closeButton.setTitleColor(UIColor(red: 0xe9 / 255.0, green: 0xdc / 255.0,
                                         blue: 0xc0 / 255.0, alpha: 1), for: .normal)
        closeButton.backgroundColor = UIColor(red: 0x22 / 255.0, green: 0x28 / 255.0,
                                             blue: 0x33 / 255.0, alpha: 1)
        closeButton.layer.cornerRadius = 6
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        let guide = view.safeAreaLayoutGuide
        var constraints: [NSLayoutConstraint] = [
            titleLabel.topAnchor.constraint(equalTo: guide.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            titleLabel.heightAnchor.constraint(equalToConstant: 32),

            contentView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            contentView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            contentView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),

            closeButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            closeButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            closeButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16),
            closeButton.heightAnchor.constraint(equalToConstant: 48)
        ]
        let hasBottomAction = action == .exchange || action == .ad
        if action == .exchange {
            constraints += [
                inputField.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
                inputField.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
                inputField.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -12),
                inputField.heightAnchor.constraint(equalToConstant: 44),
                actionButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
                actionButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
                actionButton.bottomAnchor.constraint(equalTo: closeButton.topAnchor, constant: -12),
                actionButton.heightAnchor.constraint(equalToConstant: 48),
                contentView.bottomAnchor.constraint(equalTo: inputField.topAnchor, constant: -12)
            ]
        } else if action == .ad {
            constraints += [
                watchButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
                watchButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
                watchButton.bottomAnchor.constraint(equalTo: claimButton.topAnchor, constant: -10),
                watchButton.heightAnchor.constraint(equalToConstant: 48),
                claimButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
                claimButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
                claimButton.bottomAnchor.constraint(equalTo: signButton.topAnchor, constant: -10),
                claimButton.heightAnchor.constraint(equalToConstant: 48),
                signButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
                signButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
                signButton.bottomAnchor.constraint(equalTo: closeButton.topAnchor, constant: -12),
                signButton.heightAnchor.constraint(equalToConstant: 44),
                contentView.bottomAnchor.constraint(equalTo: watchButton.topAnchor, constant: -12)
            ]
        } else {
            constraints.append(contentView.bottomAnchor.constraint(equalTo: closeButton.topAnchor, constant: -12))
        }
        if !hasBottomAction && action != .exchange && action != .ad {
            // 排行榜 / 成就 / 购买卡密：内容直接铺到关闭按钮上方
        }
        NSLayoutConstraint.activate(constraints)
    }

    // MARK: - 网络

    private func requestURL(_ name: String) -> URL? {
        guard let base = baseURLString, let baseURL = URL(string: base) else { return nil }
        var components = URLComponents()
        components.scheme = baseURL.scheme
        components.host = baseURL.host
        components.port = baseURL.port
        components.path = "/LHJ/" + name
        var items = [
            URLQueryItem(name: "device", value: deviceID),
            URLQueryItem(name: "hold", value: "\(GameModel.shared.score)"),
            URLQueryItem(name: "topScore", value: "\(GameModel.shared.topScore)")
        ]
        if name == "exchange" {
            items.append(URLQueryItem(name: "points", value: inputField.text ?? ""))
        }
        // 与安卓 LhjSign 一致：先拼 ts，再对整个 URL 做 MD5 签名
        items.append(URLQueryItem(name: "ts", value: "\(Int(Date().timeIntervalSince1970))"))
        components.queryItems = items
        guard let unsigned = components.url else { return nil }
        let raw = unsigned.absoluteString
        let sign = LHJWebViewController.md5(raw + "|" + LHJWebViewController.signSecret)
        return URL(string: raw + "&sign=" + sign)
    }

    private func send(_ name: String, mode: Mode) {
        guard let url = requestURL(name) else {
            contentView.text = "提示：地址配置错误"
            return
        }
        actionButton.isEnabled = false
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let headerSign = (response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "X-LHJ-Sign")
            let text: String
            if let data = data, let body = String(data: data, encoding: .utf8) {
                text = body
            } else {
                text = "ERR|NET|网络异常，请检查网络后重试"
            }
            DispatchQueue.main.async {
                self?.handle(text, mode: mode, sign: headerSign)
            }
        }.resume()
    }

    /// 应用后台配置（config 接口内容）
    private func applyConfig(_ body: String) {
        let fields = body.components(separatedBy: "|")
        guard fields.count >= 8 else { return }
        Config.adURL = fields[0]
        Config.buyURL = fields[1]
        Config.adReward = Int(fields[2]) ?? Config.adReward
        Config.adCooldown = Int(fields[3]) ?? Config.adCooldown
        Config.autoEnabled = (Int(fields[4]) ?? 1) == 1
        Config.autoThreshold = Int(fields[5]) ?? Config.autoThreshold
        Config.autoReward = Int(fields[6]) ?? Config.autoReward
        Config.autoInterval = Int(fields[7]) ?? Config.autoInterval
        if fields.count >= 10 {
            Config.helpText = fields[8]
            Config.moreURL = fields[9]
        }
        if fields.count >= 11, let rate = Int(fields[10]) {
            Config.winRate = rate
            GameModel.winRate = rate
        }
        if fields.count >= 12, let rate = Int(fields[11]) {
            Config.dragonRate = rate
            GameModel.dragonRate = rate
        }

        if self.action == .buy {
            if let url = LHJWebViewController.normalizedURL(Config.buyURL) {
                let page = LHJWebPageController(title: "购买卡密", url: url)
                page.modalPresentationStyle = .fullScreen
                self.present(page, animated: true, completion: nil)
            } else {
                contentView.text = "卡密购买地址暂未配置，请联系客服QQ：4711851"
            }
            return
        }
        contentView.text = "观看广告可获得 \(Config.adReward) 点游戏点数\n\n点击“观看广告”进入广告页，看完返回后点“领取奖励”。"
    }

    private func handle(_ response: String, mode: Mode, sign: String?) {
        actionButton.isEnabled = true
        let text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("OK|") else {
            showError(text)
            return
        }
        let body = String(text.dropFirst(3))
        switch mode {
        case .config:
            applyConfig(body)
        case .display:
            contentView.text = body
        case .points:
            let parts = body.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            let points = Int64(parts.first ?? "") ?? 0
            // 校验回包签名，防止被改包加点（与安卓 LhjVerify 一致）
            let header = (sign ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !header.isEmpty else {
                contentView.text = "数据校验失败，已拒绝加点"
                return
            }
            let expect = LHJWebViewController.md5(
                "POINTS|\(points)|" + LHJWebViewController.signSecret)
            guard header == expect else {
                contentView.text = "数据校验失败，已拒绝加点"
                return
            }
            if points > 0 {
                GameModel.shared.addPoints(points)
            }
            var message = parts.count > 1 ? String(parts[1]) : body
            if let range = message.range(of: "|", options: .backwards) {
                message = String(message[..<range.lowerBound])
            }
            contentView.text = message
        }
    }

    private func showError(_ text: String) {
        if text.hasPrefix("ERR|") {
            let parts = text.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            contentView.text = "提示：" + (parts.count > 2 ? String(parts[2]) : text)
        } else {
            contentView.text = text.isEmpty ? "提示：请求失败，请重试" : text
        }
    }

    /// 启动/进入游戏时拉取一次配置（自动补助、广告奖励、购买地址）
    static func fetchConfig() {
        guard let data = Data(base64Encoded: LHJWebViewController.serverBase64),
              let base = String(data: data, encoding: .utf8),
              let url = URL(string: base + "/LHJ/config?device=" +
                            (UIDevice.current.identifierForVendor?.uuidString ?? "unknown")) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data, let text = String(data: data, encoding: .utf8),
                  text.hasPrefix("OK|") else { return }
            let body = String(text.dropFirst(3))
            DispatchQueue.main.async {
                let fields = body.components(separatedBy: "|")
                guard fields.count >= 8 else { return }
                Config.adURL = fields[0]
                Config.buyURL = fields[1]
                Config.adReward = Int(fields[2]) ?? Config.adReward
                Config.adCooldown = Int(fields[3]) ?? Config.adCooldown
                Config.autoEnabled = (Int(fields[4]) ?? 1) == 1
                Config.autoThreshold = Int(fields[5]) ?? Config.autoThreshold
                Config.autoReward = Int(fields[6]) ?? Config.autoReward
                Config.autoInterval = Int(fields[7]) ?? Config.autoInterval
                if fields.count >= 10 {
                    Config.helpText = fields[8]
                    Config.moreURL = fields[9]
                }
                if fields.count >= 11, let rate = Int(fields[10]) {
                    Config.winRate = rate
                    GameModel.winRate = rate
                }
                if fields.count >= 12, let rate = Int(fields[11]) {
                    Config.dragonRate = rate
                    GameModel.dragonRate = rate
                }
            }
        }.resume()
    }

    /// 检测服务器是否可连接（进入游戏前的联网校验）
    static func checkServer(_ completion: @escaping (Bool) -> Void) {
        guard let data = Data(base64Encoded: serverBase64),
              let base = String(data: data, encoding: .utf8),
              let url = URL(string: base + "/LHJ/config?device=gate") else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { data, response, _ in
            var ok = false
            if let http = response as? HTTPURLResponse, http.statusCode == 200, data != nil {
                ok = true
            }
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }

    /// 拉取玩家当前积分（菜单里的“当前积分”）
    static func fetchInfo(_ completion: (() -> Void)? = nil) {
        guard let data = Data(base64Encoded: serverBase64),
              let base = String(data: data, encoding: .utf8),
              let url = URL(string: base + "/LHJ/info?device=" +
                            (UIDevice.current.identifierForVendor?.uuidString ?? "unknown")) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data, let text = String(data: data, encoding: .utf8),
                  text.hasPrefix("OK|") else { return }
            let body = String(text.dropFirst(3))
            let fields = body.components(separatedBy: "|")
            guard let points = Int64(fields.first ?? "") else { return }
            DispatchQueue.main.async {
                playerPoints = points
                completion?()
            }
        }.resume()
    }

    // MARK: - 事件

    @objc private func exchangeTapped() {
        let value = (inputField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard let points = Int(value), points > 0 else {
            contentView.text = "提示：请输入正确的积分数量"
            return
        }
        send("exchange", mode: .points)
    }

    @objc private func watchTapped() {
        guard let url = LHJWebViewController.normalizedURL(Config.adURL) else {
            contentView.text = "广告地址暂未配置，请联系客服QQ：4711851"
            return
        }
        // 与安卓一致：在应用内 WebView 打开广告页，返回后领取奖励
        let page = LHJWebPageController(title: "免费获取积分", url: url)
        page.modalPresentationStyle = .fullScreen
        page.onClose = { [weak self] in
            self?.adWatched = true
            self?.claimButton.isEnabled = true
            self?.contentView.text = "广告已看完，请点击“领取奖励”。"
        }
        present(page, animated: true, completion: nil)
        adWatched = true
        claimButton.isEnabled = true
        contentView.text = "广告已打开，看完后返回点击“领取奖励”。"
    }

    @objc private func signTapped() {
        send("free", mode: .display)
    }

    @objc private func claimTapped() {
        guard adWatched else {
            contentView.text = "请先点击“观看广告”，看完广告后再领取奖励。"
            return
        }
        send("ad", mode: .points)
    }

    @objc private func closeTapped() {
        dismiss(animated: true, completion: nil)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

/// 应用内网页（广告 / 购买卡密 / 更多游戏），对应安卓 LhjWebActivity、MoreActivity
final class LHJWebPageController: UIViewController, WKNavigationDelegate {

    var onClose: (() -> Void)?

    private let pageTitle: String
    private let pageURL: URL
    private let webView = WKWebView(frame: .zero)
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let indicator = UIActivityIndicatorView(style: .large)

    init(title: String, url: URL) {
        self.pageTitle = title
        self.pageURL = url
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0x11 / 255.0, green: 0x11 / 255.0,
                                      blue: 0x11 / 255.0, alpha: 1)

        titleLabel.text = pageTitle
        titleLabel.textColor = UIColor(red: 0xf5 / 255.0, green: 0xc4 / 255.0, blue: 0x51 / 255.0, alpha: 1)
        titleLabel.font = UIFont.boldSystemFont(ofSize: 20)
        titleLabel.textAlignment = .center
        view.addSubview(titleLabel)

        closeButton.setTitle("关闭", for: .normal)
        closeButton.setTitleColor(UIColor(red: 0xe9 / 255.0, green: 0xdc / 255.0, blue: 0xc0 / 255.0, alpha: 1),
                                  for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        closeButton.backgroundColor = UIColor(red: 0x22 / 255.0, green: 0x28 / 255.0, blue: 0x33 / 255.0, alpha: 1)
        closeButton.layer.cornerRadius = 6
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        webView.backgroundColor = .black
        webView.navigationDelegate = self
        view.addSubview(webView)

        indicator.color = .white
        indicator.startAnimating()
        view.addSubview(indicator)

        webView.load(URLRequest(url: pageURL))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let top = view.safeAreaInsets.top
        let bottom = view.safeAreaInsets.bottom
        titleLabel.frame = CGRect(x: 16, y: top + 8, width: view.bounds.width - 32, height: 30)
        closeButton.frame = CGRect(x: view.bounds.width - 76, y: top + 8, width: 60, height: 30)
        webView.frame = CGRect(x: 0, y: top + 46,
                               width: view.bounds.width,
                               height: view.bounds.height - top - bottom - 46)
        indicator.center = webView.center
    }

    @objc private func closeTapped() {
        onClose?()
        dismiss(animated: true, completion: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        indicator.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        indicator.stopAnimating()
        showLoadError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        indicator.stopAnimating()
        showLoadError(error)
    }

    private func showLoadError(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        let html = """
        <html><meta name="viewport" content="width=device-width,initial-scale=1">
        <body style="background:#111;color:#eee;font-family:-apple-system;padding:24px">
        <h3 style="color:#f5c451">网页打开失败</h3>
        <p>\(pageURL.absoluteString)</p>
        <p style="color:#999">\(error.localizedDescription)</p>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}
