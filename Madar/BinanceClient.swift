import Foundation

actor BinanceClient {
    static let shared = BinanceClient()

    private let hosts = [
        "https://data-api.binance.vision",
        "https://api.binance.com"
    ]
    private var activeHost: String?

    func connect() async throws -> Int64 {
        var lastError: Error?
        for host in hosts {
            do {
                let json = try await request(host: host, path: "/api/v3/time", query: [:])
                guard let dict = json as? [String: Any], let serverTime = number(dict["serverTime"])?.int64Value else {
                    throw MadarError.message("وقت المصدر غير صالح.")
                }
                activeHost = host
                return serverTime
            } catch {
                lastError = error
            }
        }
        throw lastError ?? MadarError.message("تعذّر الاتصال ببيانات Binance.")
    }

    func exchangeInfo() async throws -> Any { try await request(path: "/api/v3/exchangeInfo", query: [:]) }
    func allTickers() async throws -> Any { try await request(path: "/api/v3/ticker/24hr", query: [:]) }
    func ticker(symbol: String) async throws -> Any { try await request(path: "/api/v3/ticker/24hr", query: ["symbol": symbol]) }
    func klines(symbol: String, interval: String, limit: Int, endTime: Int64? = nil) async throws -> Any {
        var q = ["symbol": symbol, "interval": interval, "limit": String(limit)]
        if let endTime { q["endTime"] = String(endTime) }
        return try await request(path: "/api/v3/klines", query: q)
    }

    private func request(path: String, query: [String: String]) async throws -> Any {
        if let activeHost {
            return try await request(host: activeHost, path: path, query: query)
        }
        _ = try await connect()
        guard let activeHost else { throw MadarError.message("تعذّر تحديد مصدر البيانات.") }
        return try await request(host: activeHost, path: path, query: query)
    }

    private func request(host: String, path: String, query: [String: String]) async throws -> Any {
        guard var components = URLComponents(string: host + path) else {
            throw MadarError.message("رابط مصدر البيانات غير صالح.")
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw MadarError.message("تعذّر إنشاء رابط الطلب.") }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw MadarError.message("استجابة غير صالحة من مصدر البيانات.")
            }
            if http.statusCode == 418 || http.statusCode == 429 {
                throw MadarError.message("أوقف مصدر البيانات الطلبات مؤقتًا. أعد المحاولة لاحقًا.")
            }
            guard (200...299).contains(http.statusCode) else {
                if http.statusCode == 403 || http.statusCode == 451 {
                    throw MadarError.message("مصدر البيانات غير متاح من هذا الاتصال أو المنطقة.")
                }
                throw MadarError.message("تعذّر جلب البيانات من المصدر (HTTP \(http.statusCode)).")
            }
            return try JSONSerialization.jsonObject(with: data)
        } catch let error as MadarError {
            throw error
        } catch {
            throw MadarError.message("تعذّر الاتصال ببيانات Binance. تحقق من الإنترنت وإتاحة المصدر في منطقتك.")
        }
    }

    nonisolated private func number(_ value: Any?) -> NSNumber? {
        if let n = value as? NSNumber { return n }
        if let s = value as? String, let d = Double(s) { return NSNumber(value: d) }
        return nil
    }
}
