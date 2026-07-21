import Foundation
import Combine

/// Frankfurter 汇率缓存：换算先读本地；距上次成功拉取 ≥ 24h 再刷新。
@MainActor
final class ExchangeRateStore: ObservableObject {
    static let shared = ExchangeRateStore()

    private static let cacheKey = "ledger_exchange_rate_cache_v1"
    private static let refreshInterval: TimeInterval = 24 * 60 * 60
    private static let apiURL = URL(string: "https://api.frankfurter.dev/v1/latest?base=USD")!

    @Published private(set) var base: String = "USD"
    @Published private(set) var rates: [String: Double] = ["USD": 1]
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var lastErrorMessage: String?

    private var isRefreshing = false

    private init() {
        loadFromDisk()
    }

    var hasUsableRates: Bool {
        rates.isEmpty == false
    }

    /// 无缓存或超过 24h 时拉取；失败保留旧缓存。
    func ensureRatesFresh() async {
        if let fetchedAt, Date().timeIntervalSince(fetchedAt) < Self.refreshInterval, hasUsableRates {
            #if DEBUG
            print("[ExchangeRate] cache hit age=\(Int(Date().timeIntervalSince(fetchedAt)))s")
            #endif
            return
        }
        await refreshFromNetwork()
    }

    func refreshFromNetwork() async {
        guard isRefreshing == false else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: Self.apiURL)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) == false {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(FrankfurterLatestResponse.self, from: data)
            var nextRates = decoded.rates
            nextRates[decoded.base.uppercased()] = 1
            base = decoded.base.uppercased()
            rates = nextRates
            fetchedAt = Date()
            lastErrorMessage = nil
            persistToDisk()
            #if DEBUG
            print("[ExchangeRate] refreshed base=\(base) count=\(rates.count)")
            #endif
        } catch {
            lastErrorMessage = error.localizedDescription
            #if DEBUG
            print("[ExchangeRate] refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// 相对同一 `base`：`amount * (rate[to] / rate[from])`。
    func convert(amount: Double, from source: String, to target: String) -> Double {
        let fromCode = source.uppercased()
        let toCode = target.uppercased()
        if fromCode == toCode { return amount }

        guard let fromRate = rateValue(for: fromCode),
              let toRate = rateValue(for: toCode),
              fromRate > 0 else {
            #if DEBUG
            print("[ExchangeRate] missing path \(fromCode)->\(toCode); passthrough amount")
            #endif
            return amount
        }
        return amount * (toRate / fromRate)
    }

    private func rateValue(for code: String) -> Double? {
        if code == base { return 1 }
        return rates[code]
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey) else { return }
        do {
            let cached = try JSONDecoder().decode(PersistedExchangeRates.self, from: data)
            base = cached.base.uppercased()
            var loaded = cached.rates
            loaded[base] = 1
            rates = loaded
            fetchedAt = cached.fetchedAt
        } catch {
            #if DEBUG
            print("[ExchangeRate] cache decode failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func persistToDisk() {
        let payload = PersistedExchangeRates(
            base: base,
            rates: rates,
            fetchedAt: fetchedAt ?? Date()
        )
        do {
            let data = try JSONEncoder().encode(payload)
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        } catch {
            #if DEBUG
            print("[ExchangeRate] cache encode failed: \(error.localizedDescription)")
            #endif
        }
    }
}

private struct FrankfurterLatestResponse: Decodable, Sendable {
    let base: String
    let rates: [String: Double]
}

private struct PersistedExchangeRates: Codable, Sendable {
    let base: String
    let rates: [String: Double]
    let fetchedAt: Date
}
