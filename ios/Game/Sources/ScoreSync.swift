import Foundation
import UIKit

/// 点数云同步：与安卓 LhjScoreSync 一致
/// - 首次启动（本地无存档）时，用服务器最后一次上报的点数恢复
/// - 切后台 / 退出时上报当前点数
final class ScoreSync {

    static let shared = ScoreSync()

    private var baseURL: String? {
        guard let data = Data(base64Encoded: LHJWebViewController.serverBase64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private init() {}

    /// 在 App 启动时调用，注册进入后台的上报
    func start() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
    }

    /// 拉取服务器保存的点数；失败或非法返回 nil
    func fetchBalance(timeout: TimeInterval = 2.5) -> Int64? {
        guard let base = baseURL,
              var comps = URLComponents(string: base) else { return nil }
        comps.path = "/LHJ/info"
        comps.queryItems = [URLQueryItem(name: "device", value: DeviceID.value)]
        guard let url = comps.url else { return nil }
        guard let body = Self.syncGet(url: url, timeout: timeout) else { return nil }
        guard body.hasPrefix("OK|") else { return nil }
        let parts = body.dropFirst(3).components(separatedBy: "|")
        guard parts.count >= 4, let value = Int64(parts[3]), value > 0 else { return nil }
        return value
    }

    /// 上报当前点数（签名：md5(完整URL含ts + "|密钥")，sign 必须放最后）
    func report(score: Int64) {
        guard let base = baseURL,
              var comps = URLComponents(string: base) else { return }
        comps.path = "/LHJ/score"
        comps.queryItems = [
            URLQueryItem(name: "device", value: DeviceID.value),
            URLQueryItem(name: "balance", value: "\(score)"),
            URLQueryItem(name: "ts", value: "\(Int(Date().timeIntervalSince1970))"),
        ]
        guard let unsigned = comps.url else { return }
        let raw = unsigned.absoluteString
        let sign = LHJWebViewController.md5(raw + "|" + LHJWebViewController.signSecret)
        guard let url = URL(string: raw + "&sign=" + sign) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    @objc private func onEnterBackground() {
        report(score: GameModel.shared.score)
    }

    /// 同步 GET（仅首次启动恢复时使用，最多阻塞 timeout 秒）
    private static func syncGet(url: URL, timeout: TimeInterval) -> String? {
        var result: String?
        let sema = DispatchSemaphore(value: 0)
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data {
                result = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            sema.signal()
        }.resume()
        _ = sema.wait(timeout: .now() + timeout + 1)
        return result
    }
}
