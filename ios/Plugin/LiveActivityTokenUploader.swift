import Foundation
import UIKit
import WebKit

@available(iOS 16.2, *)
@MainActor
final class LiveActivityTokenUploader {
    static let shared = LiveActivityTokenUploader()
    private static let configurationKey = "LiveActivities.tokenUpload"
    private var uploads: [UUID: Upload] = [:]
    private var successfulPushToStartUploads: Set<PushToStartUploadKey> = []

    private struct Configuration: Codable, Equatable {
        let url: URL
        let origin: String
    }

    private struct PushToStartUploadKey: Hashable {
        let url: URL
        let origin: String
        let token: String
    }

    @MainActor
    private final class Upload {
        var backgroundTask: UIBackgroundTaskIdentifier = .invalid
        var task: Task<Void, Never>?
        var pushToStartKey: PushToStartUploadKey?

        func finish() {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        }
    }

    private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    func configure(url: String, origin: String) throws {
        let configuration = try validated(Configuration(url: URL(string: url) ?? URL(fileURLWithPath: "/"), origin: origin))
        let data = try JSONEncoder().encode(configuration)
        let stored = UserDefaults.standard.data(forKey: Self.configurationKey)
            .flatMap { try? JSONDecoder().decode(Configuration.self, from: $0) }
        if stored != configuration {
            reset()
        }
        UserDefaults.standard.set(data, forKey: Self.configurationKey)
        print("LiveActivities: native token upload configured")
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: Self.configurationKey)
        for upload in uploads.values {
            upload.task?.cancel()
            upload.finish()
        }
        uploads.removeAll()
        successfulPushToStartUploads.removeAll()
    }

    private func validated(_ configuration: Configuration) throws -> Configuration {
        guard let configURL = Bundle.main.url(forResource: "capacitor.config", withExtension: "json"),
              let data = try? Data(contentsOf: configURL),
              let config = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "LiveActivities", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing Capacitor configuration"])
        }
        let server = config["server"] as? [String: Any] ?? [:]
        let hostname = server["hostname"] as? String ?? "localhost"
        let scheme = server["iosScheme"] as? String ?? "capacitor"
        let serverURL = (server["url"] as? String).flatMap(URL.init(string:))
        let plugins = config["plugins"] as? [String: Any] ?? [:]
        let plugin = plugins["LiveActivities"] as? [String: Any] ?? [:]
        let allowedHosts = plugin["tokenUploadAllowedHosts"] as? [String] ?? [hostname, serverURL?.host].compactMap { $0 }
        let originURL = serverURL ?? URL(string: "\(scheme)://\(hostname)")!
        var originComponents = URLComponents(url: originURL, resolvingAgainstBaseURL: false)!
        originComponents.path = ""
        originComponents.query = nil
        originComponents.fragment = nil
        guard configuration.url.scheme == "https",
              configuration.url.user == nil, configuration.url.password == nil,
              configuration.url.fragment == nil,
              let host = configuration.url.host,
              allowedHosts.contains(where: { allowedHost in
                  let pattern = allowedHost.lowercased()
                  let uploadHost = host.lowercased()
                  return pattern.hasPrefix("*.")
                      ? uploadHost.hasSuffix(String(pattern.dropFirst()))
                      : pattern == uploadHost
              }),
              configuration.origin == originComponents.string else {
                        print("LiveActivities: rejected token upload host=\(configuration.url.host ?? "missing") scheme=\(configuration.url.scheme ?? "missing") origin=\(configuration.origin) expectedOrigin=\(originComponents.string ?? "missing") allowedHosts=\(allowedHosts.joined(separator: ","))")
            throw NSError(domain: "LiveActivities", code: 2, userInfo: [NSLocalizedDescriptionKey: "Token upload requires an allowed HTTPS host and the configured WebView origin"])
        }
        return configuration
    }

    func upload(_ payload: [String: String], method: String = "POST") {
        let label = method == "DELETE" ? "token delete" : "token upload"
        guard let data = UserDefaults.standard.data(forKey: Self.configurationKey),
              let stored = try? JSONDecoder().decode(Configuration.self, from: data),
              let configuration = try? validated(stored) else {
            print("LiveActivities: \(label) skipped (not configured)")
            return
        }
        var pushToStartKey: PushToStartUploadKey?
        if method == "POST", payload["kind"] == "push_to_start", let token = payload["token"] {
            let key = PushToStartUploadKey(url: configuration.url, origin: configuration.origin, token: token)
            guard !successfulPushToStartUploads.contains(key),
                  !uploads.values.contains(where: { $0.pushToStartKey == key }) else {
                print("LiveActivities: token upload skipped (duplicate push-to-start token)")
                return
            }
            pushToStartKey = key
        }
        let identifier = UUID()
        let upload = Upload()
        upload.pushToStartKey = pushToStartKey
        uploads[identifier] = upload
        upload.backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "LiveActivities \(label)") {
            Task { @MainActor in
                print("LiveActivities: \(label) background time expired")
                upload.task?.cancel()
                upload.finish()
            }
        }
        guard upload.backgroundTask != .invalid else {
            uploads.removeValue(forKey: identifier)
            print("LiveActivities: \(label) skipped (no background execution time)")
            return
        }
        upload.task = Task {
            defer {
                upload.finish()
                self.uploads.removeValue(forKey: identifier)
            }
            let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies {
                    continuation.resume(returning: $0)
                }
            }
            guard !Task.isCancelled else { return }
            let host = configuration.url.host!.lowercased()
            let path = configuration.url.path.isEmpty ? "/" : configuration.url.path
            let matchingCookies = cookies.filter { cookie in
                let domain = cookie.domain.lowercased()
                let domainMatches = domain.hasPrefix(".")
                    ? host == String(domain.dropFirst()) || host.hasSuffix(domain)
                    : host == domain
                let pathMatches = path == cookie.path ||
                    (path.hasPrefix(cookie.path) && (cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).hasPrefix("/")))
                return domainMatches && pathMatches && (cookie.expiresDate.map { $0 > Date() } ?? true)
            }
            do {
                var request = URLRequest(url: configuration.url)
                request.httpMethod = method
                request.httpShouldHandleCookies = false
                request.timeoutInterval = 5
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue(configuration.origin, forHTTPHeaderField: "Origin")
                request.setValue(HTTPCookie.requestHeaderFields(with: matchingCookies)["Cookie"], forHTTPHeaderField: "Cookie")
                let sessionConfiguration = URLSessionConfiguration.ephemeral
                sessionConfiguration.httpShouldSetCookies = false
                sessionConfiguration.httpCookieStorage = nil
                let session = URLSession(configuration: sessionConfiguration, delegate: RedirectBlocker(), delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                for attempt in 0..<3 {
                    try Task.checkCancellation()
                    do {
                        let (_, response) = try await session.data(for: request)
                        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                        if (200..<300).contains(status), !Task.isCancelled,
                           self.uploads[identifier] === upload, let key = upload.pushToStartKey {
                            self.successfulPushToStartUploads.insert(key)
                        }
                        print("LiveActivities: \(label) HTTP \(status)\((200..<300).contains(status) ? " ok" : " failed")")
                        return
                    } catch {
                        guard !Task.isCancelled else { return }
                        print("LiveActivities: \(label) network error (attempt \(attempt + 1)): \(error.localizedDescription)")
                        guard attempt < 2 else { return }
                        try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_000_000_000)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    print("LiveActivities: \(label) error: \(error.localizedDescription)")
                }
            }
        }
    }
}