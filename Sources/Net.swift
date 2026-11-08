import Foundation

/// 统一网络层：默认走系统信任链；遇到自签证书（本服务的 CA）时自动用宽松信任兜底。
enum Net {

    private static let config: URLSessionConfiguration = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 12
        c.timeoutIntervalForResource = 25
        c.waitsForConnectivity = false
        return c
    }()

    static let session = URLSession(configuration: config)

    private static let permissive: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 12
        c.timeoutIntervalForResource = 25
        return URLSession(configuration: c, delegate: PermissiveDelegate(), delegateQueue: nil)
    }()

    /// GET 请求，带 Bearer；自签证书时自动重试
    static func get(_ url: URL, token: String) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        if !token.isEmpty {
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        return try await data(for: req)
    }

    static func data(for req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (d, r) = try await session.data(for: req)
            guard let http = r as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            return (d, http)
        } catch let e as URLError where e.code == .serverCertificateUntrusted
                                        || e.code == .secureConnectionFailed
                                        || e.code == .cancelled {
            let (d, r) = try await permissive.data(for: req)
            guard let http = r as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            return (d, http)
        }
    }

    final class PermissiveDelegate: NSObject, URLSessionDelegate {
        func urlSession(_ session: URLSession,
                        didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }
}
