import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var signals: [Signal] = []
    @Published var isScanning = false
    @Published var status = "جاهز للفحص. لا يلزم مفتاح API."
    @Published var notice: String?
    @Published var analyzed = 0
    @Published var total = 0
    @Published var failures = 0
    @Published var progress: Double = 0
    @Published var btcState = "—"
    @Published var btcDetail = "الإغلاق مقارنة بمتوسط 200 يوم"
    @Published var lastScan: Date?
    @Published var notificationPermission = false

    let settings = SettingsStore.shared
    private var scanTask: Task<Void, Never>?
    private var autoTimer: Timer?

    private init() {}

    func prepare() async {
        notificationPermission = await NotificationManager.shared.requestAuthorization()
        configureAutoRefresh()
        BackgroundRefreshManager.shared.schedule()
    }

    func configureAutoRefresh() {
        autoTimer?.invalidate()
        autoTimer = nil
        if settings.autoRefresh {
            autoTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.isScanning else { return }
                    self.startScan()
                }
            }
        }
        BackgroundRefreshManager.shared.schedule()
    }

    func startScan() {
        if isScanning {
            scanTask?.cancel()
            status = "تم طلب إيقاف الفحص…"
            return
        }
        isScanning = true
        signals = []
        notice = nil
        analyzed = 0
        total = 0
        failures = 0
        progress = 0
        status = "جارٍ الاتصال ببيانات السوق…"
        btcState = "—"
        btcDetail = "جارٍ التحقق"

        let config = settings.config
        let notificationsEnabled = settings.notifications
        scanTask = Task {
            do {
                let result = try await MarketScanner.shared.scan(config: config) { processed, total, analyzed, failures in
                    await MainActor.run {
                        self.total = total
                        self.analyzed = analyzed
                        self.failures = failures
                        self.progress = total > 0 ? Double(processed) / Double(total) : 0
                        self.status = "جارٍ التحليل: \(processed) / \(total)"
                    }
                }
                guard !Task.isCancelled else { throw CancellationError() }
                signals = result.signals
                analyzed = result.analyzed
                total = result.total
                failures = result.failures
                btcState = result.btcState
                btcDetail = result.btcDetail
                progress = 1
                lastScan = Date()
                status = "اكتمل الفحص · \(result.analyzed) عملة محللة · \(result.signals.count) إشارة"
                if failures > 0 {
                    notice = "نتائج جزئية: تعذّر تحليل \(failures) من \(total) زوجًا."
                } else if result.signals.isEmpty {
                    notice = config.btcFilter && result.analyzed == 0 && result.total > 0 ? "فلتر بيتكوين فعّال، والاتجاه اليومي لا يحقق شرط الشراء حاليًا." : "لا توجد إشارة شراء مطابقة الآن."
                }
                if notificationsEnabled {
                    await NotificationManager.shared.notifyNewSignals(result.signals)
                }
            } catch is CancellationError {
                status = "تم إيقاف الفحص."
                notice = "النتائج الحالية أُلغيت؛ ابدأ فحصًا جديدًا عند الحاجة."
            } catch {
                status = "انتهى الفحص دون اكتمال"
                notice = error.localizedDescription
            }
            isScanning = false
            scanTask = nil
        }
    }

    func copyText(for signal: Signal) -> String {
        let p: (Double) -> String = { String(format: "%.*f", signal.digits, $0) }
        let targetLines = signal.targets.enumerated().map { idx, value in
            let pct = (value - signal.entry) / signal.entry * 100
            return "الهدف \(idx + 1): \(p(value)) USDT (+\(String(format: "%.1f", pct))%)"
        }.joined(separator: "\n")
        return """
        إشارة شراء سبوت سوينج — \(signal.symbol)
        \(signal.type)
        سعر الدخول: \(p(signal.entry)) USDT
        وقف الخسارة: \(p(signal.stop)) USDT (\(String(format: "%.1f", signal.riskPct))%)
        \(targetLines)
        الأسعار تقديرية قبل الرسوم والانزلاق؛ لا ضمان للربح.
        """
    }
}
