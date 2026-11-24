import UIKit

final class GameViewController: UIViewController, GameViewDelegate {

    private let gameView = GameView(frame: .zero)
    private var menuView: MenuView?
    private var didPlayOpen = false
    private var gateChecked = false
    private var gateOverlay: UIView?

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        gameView.frame = view.bounds
        gameView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        gameView.delegate = self
        view.addSubview(gameView)
        SoundPlayer.shared.enabled = !GameModel.shared.soundDisabled
        LHJWebViewController.fetchConfig()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !didPlayOpen {
            didPlayOpen = true
            // 安卓启动进入游戏时播放 open
            SoundPlayer.shared.play("open")
            LHJWebViewController.fetchInfo()
        }
        if !gateChecked {
            gateChecked = true
            runServerGate()
        }
    }

    // MARK: - 联网校验（对齐安卓 LhjNetGate）

    private func runServerGate() {
        showGateProgress()
        LHJWebViewController.checkServer { [weak self] result in
            guard let self = self else { return }
            self.hideGateProgress()
            switch result {
            case .ok:
                return
            case .banned:
                // 服务端封禁：不允许进入游戏
                let alert = UIAlertController(
                    title: "无法进入游戏",
                    message: "该设备已被封禁，如有疑问请联系客服。",
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "退出", style: .default) { _ in
                    exit(0)
                })
                self.present(alert, animated: true, completion: nil)
            case .unreachable:
                let alert = UIAlertController(
                    title: "无法连接服务器",
                    message: "网络未连接或服务器维护中，请检查网络后重试。",
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "重试", style: .default) { [weak self] _ in
                    self?.runServerGate()
                })
                alert.addAction(UIAlertAction(title: "退出", style: .cancel) { _ in
                    exit(0)
                })
                self.present(alert, animated: true, completion: nil)
            }
        }
    }

    private func showGateProgress() {
        guard gateOverlay == nil else { return }
        // 安卓 ProgressDialog：拦截全屏点击 + 居中黑色圆角框
        let dim = UIView(frame: view.bounds)
        dim.backgroundColor = UIColor(white: 0, alpha: 0.25)
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let box = UIView()
        box.backgroundColor = UIColor(white: 0, alpha: 0.75)
        box.layer.cornerRadius = 6
        box.translatesAutoresizingMaskIntoConstraints = false
        dim.addSubview(box)

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .white
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(spinner)

        let label = UILabel()
        label.text = "正在连接服务器..."
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 15)
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)

        NSLayoutConstraint.activate([
            box.centerXAnchor.constraint(equalTo: dim.centerXAnchor),
            box.centerYAnchor.constraint(equalTo: dim.centerYAnchor),
            box.widthAnchor.constraint(equalToConstant: 220),
            box.heightAnchor.constraint(equalToConstant: 70),

            spinner.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 20),
            spinner.centerYAnchor.constraint(equalTo: box.centerYAnchor),

            label.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])

        view.addSubview(dim)
        gateOverlay = dim
    }

    private func hideGateProgress() {
        gateOverlay?.removeFromSuperview()
        gateOverlay = nil
    }

    // MARK: - GameViewDelegate

    func gameViewDidRequestMenu(_ view: GameView) {
        showMenu()
    }

    private func showMenu() {
        guard menuView == nil else { return }
        let menu = MenuView(frame: view.bounds)
        menu.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        menu.onClose = { [weak self] in
            self?.hideMenu()
        }
        menu.onRedeem = { [weak self] in
            guard let self = self else { return }
            self.hideMenu()
            self.presentRedeem()
        }
        menu.onHelp = { [weak self] in
            self?.showHelp()
        }
        menu.onRank = { [weak self] in
            self?.openWeb(.rank)
        }
        menu.onAchievements = { [weak self] in
            self?.openWeb(.ach)
        }
        menu.onNickname = { [weak self] in
            self?.askNickname()
        }
        menu.onFreePoints = { [weak self] in
            self?.openWeb(.ad)
        }
        menu.onExchangePoints = { [weak self] in
            self?.openWeb(.exchange)
        }
        menu.onMore = { [weak self] in
            self?.openMoreGames()
        }
        view.addSubview(menu)
        menuView = menu
        LHJWebViewController.fetchInfo { [weak self] in
            self?.menuView?.updateTitle()
        }
    }

    private func openMoreGames() {
        // 与安卓 MoreActivity 一致：默认打开推荐页，后台配置了地址则优先使用
        let fallback = "http://www.baolei.in:8080/RecommendApk/more.htm"
        let configured = LHJWebViewController.Config.moreURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let address = configured.isEmpty ? fallback : configured
        guard let url = LHJWebViewController.normalizedURL(address) else { return }
        let page = LHJWebPageController(title: "更多游戏", url: url)
        page.modalPresentationStyle = .fullScreen
        present(page, animated: true, completion: nil)
    }

    private func hideMenu() {
        menuView?.removeFromSuperview()
        menuView = nil
    }

    private func presentRedeem() {
        let controller = RedeemViewController()
        controller.onSuccess = { [weak self] in
            self?.gameView.setNeedsDisplay()
        }
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true, completion: nil)
    }

    private func openWeb(_ action: LHJWebViewController.Action) {
        let controller = LHJWebViewController(action: action)
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true, completion: nil)
    }

    /// 弹出昵称输入框，调用后端 /LHJ/nickname 保存
    private func askNickname() {
        let alert = UIAlertController(title: "设置昵称", message: "设置后将显示在排行榜上（最多 12 个字符）", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "请输入昵称"
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self] _ in
            guard let self = self,
                  let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty else { return }
            self.setNickname(name)
        })
        present(alert, animated: true)
    }

    private func setNickname(_ name: String) {
        guard let baseData = Data(base64Encoded: LHJWebViewController.serverBase64),
              let base = String(data: baseData, encoding: .utf8),
              let baseURL = URL(string: base) else { return }
        var components = URLComponents()
        components.scheme = baseURL.scheme
        components.host = baseURL.host
        components.port = baseURL.port
        components.path = "/LHJ/nickname"
        var items = [
            URLQueryItem(name: "device", value: DeviceID.value),
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "ts", value: "\(Int(Date().timeIntervalSince1970))"),
        ]
        components.queryItems = items
        guard let unsigned = components.url else { return }
        let raw = unsigned.absoluteString
        let sign = LHJWebViewController.md5(raw + "|" + LHJWebViewController.signSecret)
        guard let url = URL(string: raw + "&sign=" + sign) else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            DispatchQueue.main.async {
                let ok = text.hasPrefix("OK|")
                let body = text.hasPrefix("OK|") ? String(text.dropFirst(3)) : text
                let msg = ok ? "昵称已更新" : (text.components(separatedBy: "|").last ?? text)
                let tip = UIAlertController(title: ok ? "成功" : "失败", message: msg, preferredStyle: .alert)
                tip.addAction(UIAlertAction(title: "知道了", style: .default))
                self?.present(tip, animated: true)
            }
        }.resume()
    }

    private func showHelp() {
        let help = LHJWebViewController.Config.helpText.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = help.isEmpty
            ? "1. 点击盘面格子或底部筹码下注，每次消耗 1 点；\n2. 点击“开始”扣除本轮总注并启动跑灯；\n3. 灯停下的格子若已下注即中奖，按倍率返点；\n4. 中奖后点“小/大”可押大小，赢了中奖翻倍，输了清零；\n5. 点击其他位置收分入账；\n6. 每日签到可领取 10 积分，积分可按 1:1 兑换点数；\n7. 点数不足请在菜单中“直接购买点数”；\n8. 免费获取积分：看完广告后领取奖励；\n9. 客服QQ：4711851"
            : help
        let alert = UIAlertController(title: "玩法说明", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
}
