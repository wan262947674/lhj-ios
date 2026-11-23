import UIKit

final class GameViewController: UIViewController, GameViewDelegate {

    private let gameView = GameView(frame: .zero)
    private var menuView: MenuView?
    private var didPlayOpen = false

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
