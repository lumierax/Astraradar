import Foundation

struct Candle: Sendable {
    let openTime: Int64
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
    let closeTime: Int64
}

struct Setup: Sendable {
    let type: String
    let atr: Double
    let rsi: Double
    let volumeRatio: Double
    let close: Double
    let stopRaw: Double
    let candleEnd: Int64
}

struct MarketSymbol: Sendable {
    let symbol: String
    let baseAsset: String
    let quoteAsset: String
    let status: String
    let spotAllowed: Bool
    let tickSize: Double
    let minPrice: Double
    let maxPrice: Double
}

struct Ticker: Sendable {
    let symbol: String
    let bidPrice: Double
    let askPrice: Double
    let closeTime: Int64
    let priceChangePercent: Double
    let quoteVolume: Double
    let lastPrice: Double
}

struct Candidate: Sendable {
    let meta: MarketSymbol
    let ticker: Ticker
}

struct Signal: Identifiable, Hashable, Sendable {
    var id: String { "\(symbol)-\(candleEnd)" }
    let symbol: String
    let base: String
    let type: String
    let entry: Double
    let stop: Double
    let risk: Double
    let riskPct: Double
    let targets: [Double]
    let upside: Double
    let digits: Int
    let volume: Double
    let change: Double
    let rsi: Double
    let volumeRatio: Double
    let candleEnd: Int64
    let checkedAt: Int64
    let quoteAt: Int64
    let expires: Int64

    var isExpired: Bool { expires <= Int64(Date().timeIntervalSince1970 * 1000) }
}

struct ScanConfig: Sendable {
    let limit: Int
    let minTarget: Double
    let maxStop: Double
    let btcFilter: Bool
}

struct ScanResult: Sendable {
    let signals: [Signal]
    let analyzed: Int
    let total: Int
    let failures: Int
    let btcState: String
    let btcDetail: String
}

enum MadarError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        }
    }
}
