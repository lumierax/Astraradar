import Foundation

struct SwingEngine: Sendable {
    static let h4: Int64 = 4 * 60 * 60 * 1000
    static let day: Int64 = 24 * 60 * 60 * 1000
    static let ttl: Int64 = 5 * 60 * 1000
    static let minVolume = 5_000_000.0

    static let excluded: Set<String> = [
        "USDT","USDC","BUSD","FDUSD","TUSD","USDP","DAI","USDD","USDE","USD1","EURI","EUR","AEUR","EURU","EURC","PAX","UST","USTC","VAI","DUSD","RLUSD","PYUSD","GUSD","SUSD","USDS","SUSDS","USDG","USDF","BFUSD","USDU","USDJ","USDX","XUSD","EURCV","PAXG","XAUT","GBP","AUD","BRL","TRY","RUB","BIDR","IDRT","NGN","UAH","ZAR","PLN","ARS","JPY","MXN","RON"
    ]

    static func average(_ values: [Double]) -> Double {
        values.isEmpty ? .nan : values.reduce(0, +) / Double(values.count)
    }

    static func ema(_ values: [Double], period: Int) -> [Double?] {
        var out = Array<Double?>(repeating: nil, count: values.count)
        guard values.count >= period else { return out }
        var value = average(Array(values.prefix(period)))
        out[period - 1] = value
        let alpha = 2.0 / Double(period + 1)
        guard values.count > period else { return out }
        for i in period..<values.count {
            value += alpha * (values[i] - value)
            out[i] = value
        }
        return out
    }

    static func rsi(_ values: [Double], period: Int = 14) -> Double {
        guard values.count > period else { return .nan }
        var gain = 0.0, loss = 0.0
        for i in 1...period {
            let d = values[i] - values[i - 1]
            gain += max(d, 0)
            loss += max(-d, 0)
        }
        gain /= Double(period)
        loss /= Double(period)
        if values.count > period + 1 {
            for i in (period + 1)..<values.count {
                let d = values[i] - values[i - 1]
                gain = (gain * Double(period - 1) + max(d, 0)) / Double(period)
                loss = (loss * Double(period - 1) + max(-d, 0)) / Double(period)
            }
        }
        if loss == 0 { return gain == 0 ? 50 : 100 }
        return 100 - 100 / (1 + gain / loss)
    }

    static func atr(_ bars: [Candle], period: Int = 14) -> Double {
        guard bars.count > period else { return .nan }
        var ranges: [Double] = []
        ranges.reserveCapacity(bars.count - 1)
        for i in 1..<bars.count {
            let b = bars[i], prev = bars[i - 1]
            ranges.append(max(b.high - b.low, abs(b.high - prev.close), abs(b.low - prev.close)))
        }
        var value = average(Array(ranges.prefix(period)))
        if ranges.count > period {
            for i in period..<ranges.count {
                value = (value * Double(period - 1) + ranges[i]) / Double(period)
            }
        }
        return value
    }

    static func parseBars(_ raw: Any, interval: Int64, now: Int64) throws -> (closed: [Candle], open: Candle?) {
        guard let rows = raw as? [[Any]], !rows.isEmpty else {
            throw MadarError.message("بيانات الشموع غير مكتملة.")
        }
        var all: [Candle] = []
        all.reserveCapacity(rows.count)
        for row in rows {
            guard row.count >= 7,
                  let t = int64(row[0]), let o = double(row[1]), let h = double(row[2]),
                  let l = double(row[3]), let c = double(row[4]), let v = double(row[5]),
                  let end = int64(row[6]), o > 0, c > 0, l > 0, h >= max(o, c), l <= min(o, c), v >= 0,
                  end == t + interval - 1 else {
                throw MadarError.message("تسلسل شموع غير صالح؛ استُبعد الزوج.")
            }
            if let prev = all.last, t - prev.openTime != interval {
                throw MadarError.message("تسلسل شموع غير صالح؛ استُبعد الزوج.")
            }
            all.append(Candle(openTime: t, open: o, high: h, low: l, close: c, volume: v, closeTime: end))
        }
        let closed = all.filter { $0.closeTime < now }
        let expected = (now / interval) * interval - 1
        guard let last = closed.last, last.closeTime == expected else {
            throw MadarError.message("الشموع متأخرة؛ لا يمكن اعتماد الإشارة.")
        }
        let open = all.first { $0.openTime == expected + 1 && $0.closeTime >= now }
        return (closed, open)
    }

    static func dailyTrend(_ bars: [Candle]) -> Bool {
        guard bars.count >= 210 else { return false }
        let closes = bars.map(\.close)
        let e50 = ema(closes, period: 50), e200 = ema(closes, period: 200)
        guard let lastClose = closes.last,
              let last50 = e50.last ?? nil,
              let last200 = e200.last ?? nil,
              e50.count >= 6,
              let past50 = e50[e50.count - 6] else { return false }
        return lastClose > last200 && last50 > last200 && last50 > past50
    }

    static func findSetup(daily: [Candle], four: [Candle]) -> Setup? {
        guard daily.count >= 210, four.count >= 80, dailyTrend(daily) else { return nil }
        let closes = four.map(\.close)
        let e20 = ema(closes, period: 20), e50 = ema(closes, period: 50)
        let a = atr(four), momentum = rsi(closes)
        guard let b = four.last, four.count >= 2,
              let last20 = e20.last ?? nil,
              let last50 = e50.last ?? nil,
              e20.count >= 4,
              let past20 = e20[e20.count - 4],
              a.isFinite, a > 0,
              b.close > last20, last20 > last50, last20 > past20 else { return nil }
        if momentum < 48 || momentum > 70 || (b.close - last20) / a > 2.5 { return nil }

        let previous20 = Array(four.dropLast().suffix(20))
        let baseVol = average(previous20.map(\.volume))
        let volumeRatio = baseVol > 0 ? b.volume / baseVol : 0
        let resistance = previous20.map(\.high).max() ?? .infinity
        let breakout = b.close > resistance && b.close > b.open && volumeRatio >= 1.5

        let last3 = Array(four.suffix(3))
        let recentLow = last3.map(\.low).min() ?? .infinity
        var nearAverage = false
        if e20.count >= 3 {
            let e20Slice = Array(e20.suffix(3))
            for i in 0..<min(last3.count, e20Slice.count) {
                if let avg20 = e20Slice[i], last3[i].low <= avg20 * 1.01 { nearAverage = true }
            }
        }
        let prev = four[four.count - 2]
        let pullback = nearAverage && recentLow >= last50 * 0.985 && b.close > prev.high && b.close > b.open && volumeRatio >= 1.1
        guard breakout || pullback else { return nil }

        let low10 = four.suffix(10).map(\.low).min() ?? b.low
        let stopRaw = min(low10 - 0.5 * a, b.close - 2 * a)
        guard stopRaw > 0, stopRaw < b.close else { return nil }
        return Setup(type: breakout ? "اختراق مقاومة" : "ارتداد مع الاتجاه", atr: a, rsi: momentum, volumeRatio: volumeRatio, close: b.close, stopRaw: stopRaw, candleEnd: b.closeTime)
    }

    static func roundStep(_ value: Double, step: Double) -> (value: Double, digits: Int)? {
        guard step > 0 else { return nil }
        let digits = stepDigits(step)
        let rounded = floor(value / step + 1e-8) * step
        return (Double(String(format: "%.*f", digits, rounded)) ?? rounded, digits)
    }

    static func makePlan(setup: Setup, ticker: Ticker, meta: MarketSymbol, open: Candle?, config: ScanConfig, now: Int64) -> Signal? {
        let bid = ticker.bidPrice, entry = ticker.askPrice, stamp = ticker.closeTime
        guard ticker.symbol == meta.symbol, now - stamp <= 120_000, stamp - now <= 10_000, bid > 0, entry >= bid else { return nil }
        guard (entry - bid) / entry <= 0.003,
              abs(entry - setup.close) <= min(0.75 * setup.atr, setup.close * 0.015),
              ticker.quoteVolume >= minVolume else { return nil }
        guard let roundedStop = roundStep(setup.stopRaw, step: meta.tickSize) else { return nil }
        let stop = roundedStop.value
        let risk = entry - stop
        let riskPct = risk / entry * 100
        guard stop > 0, risk > 0, riskPct <= config.maxStop, riskPct >= 0.3 else { return nil }

        var targets: [Double] = []
        for r in [3.0, 5.0, 8.0] {
            guard let target = roundStep(entry + r * risk, step: meta.tickSize)?.value else { return nil }
            targets.append(target)
        }
        guard targets.count == 3,
              stop >= meta.minPrice,
              targets[2] <= meta.maxPrice,
              targets[0] > entry, targets[1] > targets[0], targets[2] > targets[1] else { return nil }
        let upside = (targets[2] - entry) / entry * 100
        guard upside + 1e-7 >= config.minTarget else { return nil }
        guard let open, open.low > stop, open.high < targets[0], entry > stop, entry < targets[0] else { return nil }

        let expires = min(now + ttl, setup.candleEnd + 1 + h4)
        guard expires > now else { return nil }
        return Signal(symbol: meta.symbol, base: meta.baseAsset, type: setup.type, entry: entry, stop: stop, risk: risk, riskPct: riskPct, targets: targets, upside: upside, digits: roundedStop.digits, volume: ticker.quoteVolume, change: ticker.priceChangePercent, rsi: setup.rsi, volumeRatio: setup.volumeRatio, candleEnd: setup.candleEnd, checkedAt: now, quoteAt: stamp, expires: expires)
    }

    static func choosePairs(exchangeInfo: Any, tickersRaw: Any, limit: Int) throws -> [Candidate] {
        guard let info = exchangeInfo as? [String: Any], let symbols = info["symbols"] as? [[String: Any]],
              let tickerRows = tickersRaw as? [[String: Any]] else {
            throw MadarError.message("تعذر قراءة قائمة السوق.")
        }
        let tickers = tickerRows.compactMap(parseTicker)
        let tickMap = Dictionary(uniqueKeysWithValues: tickers.map { ($0.symbol, $0) })
        var candidates: [Candidate] = []
        for s in symbols {
            guard let symbol = s["symbol"] as? String,
                  let status = s["status"] as? String,
                  let base = s["baseAsset"] as? String,
                  let quote = s["quoteAsset"] as? String,
                  quote == "USDT", status == "TRADING",
                  (s["isSpotTradingAllowed"] as? Bool) == true,
                  !excluded.contains(base),
                  !base.hasSuffix("UP"), !base.hasSuffix("DOWN"), !base.hasSuffix("BULL"), !base.hasSuffix("BEAR"),
                  symbol.range(of: "^[A-Z0-9]{1,30}USDT$", options: .regularExpression) != nil,
                  let filters = s["filters"] as? [[String: Any]],
                  let priceFilter = filters.first(where: { ($0["filterType"] as? String) == "PRICE_FILTER" }),
                  let tickSize = double(priceFilter["tickSize"]), tickSize > 0,
                  let ticker = tickMap[symbol], ticker.quoteVolume >= minVolume, ticker.lastPrice > 0 else { continue }
            let minPrice = double(priceFilter["minPrice"]) ?? 0
            let maxPrice = double(priceFilter["maxPrice"]) ?? Double.greatestFiniteMagnitude
            candidates.append(Candidate(meta: MarketSymbol(symbol: symbol, baseAsset: base, quoteAsset: quote, status: status, spotAllowed: true, tickSize: tickSize, minPrice: minPrice, maxPrice: maxPrice), ticker: ticker))
        }
        return Array(candidates.sorted { $0.ticker.quoteVolume > $1.ticker.quoteVolume }.prefix(limit))
    }

    static func parseTicker(_ dict: [String: Any]) -> Ticker? {
        guard let symbol = dict["symbol"] as? String,
              let bid = double(dict["bidPrice"]), let ask = double(dict["askPrice"]),
              let closeTime = int64(dict["closeTime"]), let change = double(dict["priceChangePercent"]),
              let quoteVolume = double(dict["quoteVolume"]), let lastPrice = double(dict["lastPrice"]) else { return nil }
        return Ticker(symbol: symbol, bidPrice: bid, askPrice: ask, closeTime: closeTime, priceChangePercent: change, quoteVolume: quoteVolume, lastPrice: lastPrice)
    }

    static func stepDigits(_ step: Double) -> Int {
        var value = step
        var digits = 0
        while digits < 12 && abs(value.rounded() - value) > 1e-10 {
            value *= 10
            digits += 1
        }
        return digits
    }

    static func double(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    static func int64(_ value: Any?) -> Int64? {
        if let n = value as? NSNumber { return n.int64Value }
        if let s = value as? String, let d = Double(s) { return Int64(d) }
        return nil
    }
}
