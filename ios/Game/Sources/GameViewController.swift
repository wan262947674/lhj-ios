import UIKit

final class GameViewController: UIViewController, GameViewDelegate {

    private let gameView = GameView(frame: .zero)
    private var menuView: MenuView?
    private var gateAlert: UIAlertController?
    private var gateChecked = false

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
        if !gateChecked {
            gateChecked = true
            checkServerGate()
        }
    }

    /// 未连接后台时阻止进入游戏
    private func checkServerGate() {
        guard gateAlert == nil else { return }
        let progress = UIAlertController(title: nil, message: "正在连接服务器...", preferredStyle: .alert)
        present(progress, animated: true, completion: nil)
        gateAlert = progress

        LHJWebViewController.checkServer { [weak self] ok in
            guard let self = self else { return }
            self.gateAlert?.dismiss(animated: true) {
                self.gateAlert = nil
                guard !ok else { return }
                let fail = UIAlertController(
                    title: "无法连接服务器",
                    message: "网络未连接或服务器维护中，请检查网络后重试。",
                    preferredStyle: .alert)
                fail.addAction(UIAlertAction(title: "重试", style: .default) { _ in
                    self.checkServerGate()
                })
                fail.addAction(UIAlertAction(title: "退出", style: .cancel) { _ in
                    exit(0)
                })
                self.present(fail, animated: true, completion: nil)
            }
        }
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
        guard let url = URL(string: LHJWebViewController.Config.moreURL),
              !LHJWebViewController.Config.moreURL.isEmpty else {
            let alert = UIAlertController(title: nil, message: "更多游戏地址暂未配置", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "知道了", style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
            return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
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
        hideMenu()
        let controller = LHJWebViewController(action: action)
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true, completion: nil)
    }

    private func showHelp() {
        let help = LHJWebViewController.Config.helpText.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = help.isEmpty
            ? "1. 点击盘面格子或底部筹码下注，每次消耗 1 点；\n2. 点击“开始”扣除本轮总注并启动跑灯；\n3. 灯停下的格子若已下注即中奖，按倍率返点；\n4. 中奖后点“小/大”可押大小，赢了中奖翻倍，输了清零；\n5. 点击其他位置收分入账；\n6. 点数不足请在菜单中“直接购买点数”；\n7. 免费获取积分：看完广告后领取奖励；\n8. 客服QQ：4711851"
            : help
        let alert = UIAlertController(title: "玩法说明", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
}
