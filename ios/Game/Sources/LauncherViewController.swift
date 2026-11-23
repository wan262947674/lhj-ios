import UIKit

/// 启动页：与安卓 LauncherActivity 一致
/// 1. 显示 title 背景图 + “游戏载入中...” 加载框
/// 2. 约 1.7 秒后隐藏加载框，显示“开始游戏”按钮
/// 3. 点击开始游戏进入 GameViewController
final class LauncherViewController: UIViewController {

    private let backgroundView = UIImageView()
    private let startButton = UIButton(type: .custom)

    private let loadingBox = UIView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let loadingLabel = UILabel()

    private var launchTime: CFTimeInterval = 0
    private var minDelayPassed = false
    private var serverResult: Bool?
    private var revealed = false
    private var started = false
    private var failAlert: UIAlertController?

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupBackground()
        setupStartButton()
        setupLoadingBox()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard launchTime == 0 else { return }
        launchTime = CACurrentMediaTime()

        spinner.startAnimating()
        loadingBox.isHidden = false
        startButton.isHidden = true

        // 与安卓一致：进入启动页即拉取运营配置
        LHJWebViewController.fetchConfig()

        // 1.7 秒后开始显示“开始游戏”（安卓 Thread.sleep 0x6a4）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { [weak self] in
            self?.minDelayPassed = true
            self?.revealWhenReady()
        }

        checkServer()
    }

    // MARK: - UI

    private func setupBackground() {
        backgroundView.image = UIImage(named: "title") ?? UIImage(named: "title.jpg")
        backgroundView.contentMode = .scaleAspectFill
        backgroundView.clipsToBounds = true
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backgroundView)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupStartButton() {
        // 安卓 launcher.xml：160dp x 65dp，水平居中，距底部约 100dp
        let image = UIImage(named: "start") ?? UIImage(named: "start.png")
        startButton.setImage(image, for: .normal)
        startButton.imageView?.contentMode = .scaleToFill
        startButton.adjustsImageWhenHighlighted = true
        startButton.isHidden = true
        startButton.addTarget(self, action: #selector(startGame), for: .touchUpInside)
        startButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(startButton)
        NSLayoutConstraint.activate([
            startButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            startButton.widthAnchor.constraint(equalToConstant: 160),
            startButton.heightAnchor.constraint(equalToConstant: 65),
            startButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -100),
        ])
    }

    private func setupLoadingBox() {
        // 安卓 ProgressDialog：黑色半透明圆角框 + 转圈 + “游戏载入中...”
        loadingBox.backgroundColor = UIColor(white: 0, alpha: 0.75)
        loadingBox.layer.cornerRadius = 6
        loadingBox.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingBox)

        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        loadingBox.addSubview(spinner)

        loadingLabel.text = "游戏载入中..."
        loadingLabel.textColor = .white
        loadingLabel.font = UIFont.systemFont(ofSize: 15)
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingBox.addSubview(loadingLabel)

        NSLayoutConstraint.activate([
            loadingBox.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingBox.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            loadingBox.widthAnchor.constraint(equalToConstant: 200),
            loadingBox.heightAnchor.constraint(equalToConstant: 70),

            spinner.leadingAnchor.constraint(equalTo: loadingBox.leadingAnchor, constant: 20),
            spinner.centerYAnchor.constraint(equalTo: loadingBox.centerYAnchor),

            loadingLabel.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 12),
            loadingLabel.trailingAnchor.constraint(lessThanOrEqualTo: loadingBox.trailingAnchor, constant: -12),
            loadingLabel.centerYAnchor.constraint(equalTo: loadingBox.centerYAnchor),
        ])
    }

    // MARK: - 服务器检测

    private func checkServer() {
        serverResult = nil
        LHJWebViewController.checkServer { [weak self] ok in
            DispatchQueue.main.async {
                self?.serverResult = ok
                self?.revealWhenReady()
            }
        }
    }

    private func revealWhenReady() {
        guard !revealed, minDelayPassed, let ok = serverResult else { return }
        if ok {
            revealed = true
            spinner.stopAnimating()
            loadingBox.isHidden = true
            startButton.isHidden = false
        } else {
            showServerFail()
        }
    }

    private func showServerFail() {
        guard failAlert == nil else { return }
        let alert = UIAlertController(
            title: "无法连接服务器",
            message: "网络未连接或服务器维护中，请检查网络后重试。",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "重试", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.failAlert = nil
            self.checkServer()
        })
        alert.addAction(UIAlertAction(title: "退出", style: .cancel) { _ in
            exit(0)
        })
        failAlert = alert
        present(alert, animated: true, completion: nil)
    }

    // MARK: - 开始游戏

    @objc private func startGame() {
        guard !started else { return }
        started = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        guard let window = view.window else { return }
        window.rootViewController = GameViewController()
        window.makeKeyAndVisible()
    }
}
