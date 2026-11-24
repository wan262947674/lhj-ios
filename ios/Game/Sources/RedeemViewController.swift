import UIKit

/// 卡密充值页（对应安卓 RedeemActivity，界面保持一致，不显示服务器地址）
final class RedeemViewController: UIViewController, UITextFieldDelegate {

    var onSuccess: (() -> Void)?

    private let serverBase64 = "aHR0cDovLzEuMTE3LjIwNC4xMzc6ODA4MA=="

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let cardField = UITextField()
    private let redeemButton = UIButton(type: .system)
    private let buyButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let closeButton = UIButton(type: .system)

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0x11 / 255.0, green: 0x11 / 255.0, blue: 0x11 / 255.0, alpha: 1)

        closeButton.setTitle("关闭", for: .normal)
        closeButton.setTitleColor(UIColor(red: 0x9a / 255.0, green: 0xa3 / 255.0, blue: 0xb2 / 255.0, alpha: 1), for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        titleLabel.text = "卡密充值"
        titleLabel.textColor = UIColor(red: 0xf5 / 255.0, green: 0xc4 / 255.0, blue: 0x51 / 255.0, alpha: 1)
        titleLabel.font = UIFont.boldSystemFont(ofSize: 22)
        titleLabel.textAlignment = .center
        view.addSubview(titleLabel)

        subtitleLabel.text = "输入卡密，兑换后点数立即到账"
        subtitleLabel.textColor = UIColor(red: 0x9a / 255.0, green: 0xa3 / 255.0, blue: 0xb2 / 255.0, alpha: 1)
        subtitleLabel.font = UIFont.systemFont(ofSize: 14)
        subtitleLabel.textAlignment = .center
        view.addSubview(subtitleLabel)

        cardField.placeholder = "LHJ-XXXX-XXXX-XXXX"
        cardField.textColor = .white
        cardField.attributedPlaceholder = NSAttributedString(
            string: "LHJ-XXXX-XXXX-XXXX",
            attributes: [.foregroundColor: UIColor(red: 0x77 / 255.0, green: 0x80 / 255.0, blue: 0x8f / 255.0, alpha: 1)])
        cardField.backgroundColor = UIColor(red: 0x22 / 255.0, green: 0x28 / 255.0, blue: 0x33 / 255.0, alpha: 1)
        cardField.font = UIFont.systemFont(ofSize: 16)
        cardField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        cardField.leftViewMode = .always
        cardField.layer.cornerRadius = 4
        cardField.autocorrectionType = .no
        cardField.autocapitalizationType = .allCharacters
        cardField.returnKeyType = .done
        cardField.delegate = self
        view.addSubview(cardField)

        redeemButton.setTitle("立即兑换", for: .normal)
        redeemButton.setTitleColor(.black, for: .normal)
        redeemButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
        redeemButton.backgroundColor = UIColor(red: 0xf5 / 255.0, green: 0xc4 / 255.0, blue: 0x51 / 255.0, alpha: 1)
        redeemButton.layer.cornerRadius = 4
        redeemButton.addTarget(self, action: #selector(redeemTapped), for: .touchUpInside)
        view.addSubview(redeemButton)

        buyButton.setTitle("购买卡密", for: .normal)
        buyButton.setTitleColor(UIColor(red: 0xf5 / 255.0, green: 0xc4 / 255.0, blue: 0x51 / 255.0, alpha: 1),
                                for: .normal)
        buyButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
        buyButton.backgroundColor = UIColor(red: 0x22 / 255.0, green: 0x28 / 255.0, blue: 0x33 / 255.0, alpha: 1)
        buyButton.layer.cornerRadius = 4
        buyButton.layer.borderWidth = 1
        buyButton.layer.borderColor = UIColor(red: 0x6b / 255.0, green: 0x5a / 255.0, blue: 0x3a / 255.0, alpha: 1).cgColor
        buyButton.addTarget(self, action: #selector(buyTapped), for: .touchUpInside)
        view.addSubview(buyButton)

        statusLabel.text = "兑换成功后自动增加游戏点数"
        statusLabel.textColor = UIColor(red: 0x9a / 255.0, green: 0xa3 / 255.0, blue: 0xb2 / 255.0, alpha: 1)
        statusLabel.font = UIFont.systemFont(ofSize: 12)
        statusLabel.numberOfLines = 0
        view.addSubview(statusLabel)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        let safeTop = view.safeAreaInsets.top
        let padding: CGFloat = 28
        let contentWidth = width - padding * 2

        closeButton.frame = CGRect(x: padding, y: safeTop + 8, width: 60, height: 30)
        titleLabel.frame = CGRect(x: padding, y: safeTop + 64, width: contentWidth, height: 32)
        subtitleLabel.frame = CGRect(x: padding, y: titleLabel.frame.maxY + 12, width: contentWidth, height: 20)
        cardField.frame = CGRect(x: padding, y: subtitleLabel.frame.maxY + 28, width: contentWidth, height: 56)
        redeemButton.frame = CGRect(x: padding, y: cardField.frame.maxY + 24, width: contentWidth, height: 50)
        buyButton.frame = CGRect(x: padding, y: redeemButton.frame.maxY + 12, width: contentWidth, height: 46)
        statusLabel.frame = CGRect(x: padding, y: buyButton.frame.maxY + 18, width: contentWidth, height: 44)
    }

    // MARK: - 操作

    @objc private func closeTapped() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func buyTapped() {
        let controller = LHJWebViewController(action: .buy)
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true, completion: nil)
    }

    @objc private func redeemTapped() {
        view.endEditing(true)
        let card = (cardField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !card.isEmpty else {
            setStatus("请输入卡密")
            return
        }
        guard let endpoint = RedeemViewController.endpoint(from: serverBase64) else {
            setStatus("兑换失败: 服务器未配置")
            return
        }

        setStatus("正在兑换，请稍候...")
        redeemButton.isEnabled = false

        let device = DeviceID.value
        let body = "card=\(RedeemViewController.encode(card))"
            + "&device=\(RedeemViewController.encode(device))"
            + "&pkg=\(RedeemViewController.encode("lhj.baolei.in"))"
            + "&ver=1.8"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/x-www-form-urlencoded;charset=UTF-8",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            let text: String?
            if let data = data {
                text = String(data: data, encoding: .utf8)
            } else {
                text = nil
            }
            DispatchQueue.main.async {
                self?.handleResponse(text, error: error)
            }
        }.resume()
    }

    private func handleResponse(_ text: String?, error: Error?) {
        if error != nil || text == nil {
            setStatus("兑换失败: 网络异常，请检查服务器地址")
            redeemButton.isEnabled = true
            return
        }
        let response = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if response.hasPrefix("OK|") {
            let rest = String(response.dropFirst(3))
            let pointsText = rest.split(separator: "|", maxSplits: 1).first.map { String($0) } ?? rest
            guard let points = Int(pointsText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                setStatus("兑换失败: 返回数据异常")
                redeemButton.isEnabled = true
                return
            }
            GameModel.shared.addPoints(Int64(points))
            onSuccess?()
            setStatus("兑换成功，获得 \(points) 点")
            SoundPlayer.shared.play("bswin")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.dismiss(animated: true, completion: nil)
            }
            return
        }

        // 失败格式：ERR|码|消息
        let parts = response.split(separator: "|", omittingEmptySubsequences: false)
        var message = response
        if parts.count >= 3 {
            message = String(parts[2])
        } else if parts.count == 2 {
            message = String(parts[1])
        }
        setStatus("兑换失败: \(message)")
        redeemButton.isEnabled = true
    }

    private func setStatus(_ text: String) {
        statusLabel.text = text
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        redeemTapped()
        return true
    }

    // MARK: - 服务器地址（仅内部使用，界面不展示）

    private static func endpoint(from base64: String) -> URL? {
        guard let data = Data(base64Encoded: base64),
              var base = String(data: data, encoding: .utf8) else { return nil }
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.hasPrefix("http://") && !base.hasPrefix("https://") {
            base = "http://" + base
        }
        if !base.hasSuffix("/") { base += "/" }
        if !base.hasSuffix("LHJ/") { base += "LHJ/" }
        return URL(string: base)
    }

    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
