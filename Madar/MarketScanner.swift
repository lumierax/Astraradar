import Foundation

actor MarketScanner {
    static let shared = MarketScanner()
    private let client = BinanceClient.shared

    func scan(config: ScanConfig, progress: (@Sendable (Int, Int, Int, Int) async -> Void)? = nil) async throws -> ScanResult {
        let serverStart = try await client.connect()
        let clock = MarketClock(serverStart: serverStart)
        let initialNow = clock.now()
        async let infoTask = client.exchangeInfo()
        async let tickersTask = client.allTickers()
        async let btcTask = client.klines(symbol: "BTCUSDT", interval: "1d", limit: 320, endTime: initialNow)
        let (info, tickersRaw, btcRaw) = try await (infoTask, tickersTask, btcTask)

        let btcBars = try SwingEngine.parseBars(btcRaw, interval: SwingEngine.day, now: initialNow).closed
        guard btcBars.count >= 210 else { throw MadarError.message("سجل بيتكوين غير كافٍ.") }
        let btcCloses = btcBars.map(\.close)
        let e200 = SwingEngine.ema(btcCloses, period: 200)
        let btcEMA200 = e200.last ?? nil
        let btcOK = btcEMA200.map { (btcCloses.last ?? 0) > $0 } ?? false
        let btcState = btcOK ? "صاعد" : "غير مؤكد"
        let btcDetail = btcOK ? "أعلى EMA200 · شمعة يومية مغلقة" : "أدنى أو عند EMA200 · شمعة يومية مغلقة"

        let pairs = try SwingEngine.choosePairs(exchangeInfo: info, tickersRaw: tickersRaw, limit: config.limit)
        if config.btcFilter && !btcOK {
            return ScanResult(signals: [], analyzed: 0, total: pairs.count, failures: 0, btcState: btcState, btcDetail: btcDetail)
        }
        if pairs.isEmpty {
            return ScanResult(signals: [], analyzed: 0, total: 0, failures: 0, btcState: btcState, btcDetail: btcDetail)
        }

        var signals: [Signal] = []
        var analyzed = 0
        var failures = 0
        var processed = 0

        // Concurrency is intentionally limited to three workers, matching the HTML scanner.
        let queue = PairQueue(items: pairs)
        try await withThrowingTaskGroup(of: WorkerResult.self) { group in
            for _ in 0..<min(3, pairs.count) {
                group.addTask { [client] in
                    var localSignals: [Signal] = []
                    var localAnalyzed = 0
                    var localFailures = 0
                    var localProcessed = 0
                    while let item = await queue.next() {
                        do {
                            if let signal = try await Self.analyzePair(item, clock: clock, config: config, client: client) {
                                localSignals.append(signal)
                            }
                            localAnalyzed += 1
                        } catch {
                            localFailures += 1
                        }
                        localProcessed += 1
                    }
                    return WorkerResult(signals: localSignals, analyzed: localAnalyzed, failures: localFailures, processed: localProcessed)
                }
            }
            for try await result in group {
                signals.append(contentsOf: result.signals)
                analyzed += result.analyzed
                failures += result.failures
                processed += result.processed
                await progress?(processed, pairs.count, analyzed, failures)
            }
        }

        if analyzed == 0 && failures > 0 {
            throw MadarError.message("لم يكتمل تحليل أي زوج بسبب أخطاء البيانات؛ لا يمكن تقييم وجود فرص شراء.")
        }
        let sorted = signals.sorted { a, b in
            if a.volumeRatio == b.volumeRatio { return a.riskPct < b.riskPct }
            return a.volumeRatio > b.volumeRatio
        }
        return ScanResult(signals: sorted, analyzed: analyzed, total: pairs.count, failures: failures, btcState: btcState, btcDetail: btcDetail)
    }

    private static func analyzePair(_ item: Candidate, clock: MarketClock, config: ScanConfig, client: BinanceClient) async throws -> Signal? {
        let firstNow = clock.now()
        let dailyRaw = try await client.klines(symbol: item.meta.symbol, interval: "1d", limit: 320, endTime: firstNow)
        let daily = try SwingEngine.parseBars(dailyRaw, interval: SwingEngine.day, now: firstNow).closed
        guard SwingEngine.dailyTrend(daily) else { return nil }
        let setupNow = clock.now()
        let fourRaw = try await client.klines(symbol: item.meta.symbol, interval: "4h", limit: 260, endTime: setupNow)
        let parsed = try SwingEngine.parseBars(fourRaw, interval: SwingEngine.h4, now: setupNow)
        guard let setup = SwingEngine.findSetup(daily: daily, four: parsed.closed) else { return nil }

        async let tickerRawTask = client.ticker(symbol: item.meta.symbol)
        async let currentRawTask = client.klines(symbol: item.meta.symbol, interval: "4h", limit: 3)
        let (tickerRaw, currentRaw) = try await (tickerRawTask, currentRawTask)
        guard let tickerDict = tickerRaw as? [String: Any], let ticker = SwingEngine.parseTicker(tickerDict) else {
            throw MadarError.message("بيانات السعر الحالي غير صالحة.")
        }
        let currentNow = clock.now()
        let current = try SwingEngine.parseBars(currentRaw, interval: SwingEngine.h4, now: currentNow)
        guard current.closed.last?.closeTime == setup.candleEnd else { return nil }
        return SwingEngine.makePlan(setup: setup, ticker: ticker, meta: item.meta, open: current.open, config: config, now: currentNow)
    }
}

private struct WorkerResult: Sendable {
    let signals: [Signal]
    let analyzed: Int
    let failures: Int
    let processed: Int
}

private actor PairQueue {
    private var items: [Candidate]
    private var index = 0
    init(items: [Candidate]) { self.items = items }
    func next() -> Candidate? {
        guard index < items.count else { return nil }
        defer { index += 1 }
        return items[index]
    }
}

private struct MarketClock: Sendable {
    let serverStart: Int64
    let localStart: Int64

    init(serverStart: Int64) {
        self.serverStart = serverStart
        self.localStart = Int64(Date().timeIntervalSince1970 * 1000)
    }

    func now() -> Int64 {
        serverStart + (Int64(Date().timeIntervalSince1970 * 1000) - localStart)
    }
}
