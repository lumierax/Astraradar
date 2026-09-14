import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    controls
                    summary
                    if let notice = model.notice {
                        Text(notice)
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    }
                    results
                    method
                    footer
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("مدار")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: settings.autoRefresh) { _, _ in model.configureAutoRefresh() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("محرك إشارات العملات الرقمية")
                .font(.caption)
                .foregroundStyle(.green)
            Text("رادار الشراء")
                .font(.largeTitle.bold())
            Text("فرص سبوت سوينج، بثلاثة أهداف ممتدة ووقف خسارة واضح.")
                .foregroundStyle(.secondary)
            Text("إشارة 4H / تأكيد الاتجاه 1D")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            picker("نطاق الفحص · الأعلى سيولة", selection: $settings.universe, values: [30, 50, 100, 150]) { "\($0) عملة" }
            picker("الحد الأدنى للهدف الثالث", selection: $settings.minTarget, values: [15, 20, 30, 40]) { "+\(Int($0))%" }
            picker("أقصى بُعد لوقف الخسارة", selection: $settings.maxStop, values: [6, 8, 10, 12]) { "\(Int($0))% من سعر الدخول" }

            Toggle("تأكيد اتجاه بيتكوين", isOn: $settings.btcFilter)
            Toggle("تحديث كل 5 دقائق أثناء فتح التطبيق", isOn: $settings.autoRefresh)
            Toggle("إشعار عند ظهور إشارة جديدة", isOn: $settings.notifications)

            Button(action: model.startScan) {
                HStack {
                    Image(systemName: model.isScanning ? "stop.fill" : "magnifyingglass")
                    Text(model.isScanning ? "إيقاف الفحص" : "فحص السوق")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.isScanning ? .gray : .green)

            if model.isScanning {
                ProgressView(value: model.progress)
            }
            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func picker<T: Hashable & Comparable>(_ title: String, selection: Binding<T>, values: [T], label: @escaping (T) -> String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { value in Text(label(value)).tag(value) }
            }
            .labelsHidden()
        }
    }

    private var summary: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            stat("إشارات شراء نشطة", value: "\(model.signals.filter { !$0.isExpired }.count)")
            stat("عملات تم تحليلها", value: "\(model.analyzed)", detail: model.total > 0 ? "من \(model.total) زوجًا" : nil)
            stat("اتجاه بيتكوين اليومي", value: model.btcState, detail: model.btcDetail)
            stat("آخر فحص", value: model.lastScan.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
        }
    }

    private func stat(_ title: String, value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold())
            if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("فرص الشراء").font(.title3.bold())
                Text("\(model.signals.count)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.secondary.opacity(0.15), in: Capsule())
                Spacer()
                Text("3R / 5R / 8R").font(.caption).foregroundStyle(.secondary)
            }
            if model.signals.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.green)
                    Text(model.isScanning ? "جارٍ البحث عن فرص مطابقة…" : "السوق يتغيّر. ابدأ الفحص.")
                        .font(.headline)
                    Text("يعرض التطبيق سعر الدخول والأهداف ووقف الخسارة فقط عند اكتمال جميع الشروط.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 190)
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            } else {
                ForEach(model.signals) { signal in SignalCard(signal: signal) }
            }
        }
    }

    private var method: some View {
        DisclosureGroup("كيف تُحسب الإشارات والأهداف؟") {
            VStack(alignment: .leading, spacing: 8) {
                Text("اختيار السوق: أزواج سبوت USDT المتاحة للتداول، بسيولة يومية لا تقل عن 5 ملايين USDT.")
                Text("تأكيد يومي: الإغلاق فوق EMA200، وEMA50 فوق EMA200 وصاعد خلال آخر 5 شموع.")
                Text("إشارة 4 ساعات: EMA20 أعلى من EMA50 وصاعد، وRSI14 بين 48 و70، مع اختراق بحجم قوي أو ارتداد قرب EMA20.")
                Text("الوقف: الأقل من قاع آخر 10 شموع ناقص 0.5 ATR14 أو إغلاق الإشارة ناقص 2 ATR14.")
                Text("الأهداف: R = الدخول − الوقف، ثم 3R و5R و8R.")
                Text("هذه قواعد فنية قابلة للفحص وليست ضمانًا للربح أو نصيحة مالية شخصية.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var footer: some View {
        Text("بيانات Binance العامة · شموع مغلقة فقط · لا يتصل التطبيق بحسابك ولا ينفذ أوامر.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.bottom, 16)
    }
}

struct SignalCard: View {
    let signal: Signal
    @EnvironmentObject private var model: AppModel
    @State private var copied = false

    private func p(_ x: Double) -> String { String(format: "%.*f", signal.digits, x) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(signal.isExpired ? "لقطة منتهية · أعد الفحص" : "إشارة شراء سبوت")
                        .font(.caption.bold()).foregroundStyle(signal.isExpired ? .orange : .green)
                    Text("\(signal.base) / USDT").font(.title2.bold()).environment(\.layoutDirection, .leftToRight)
                    Text(signal.type).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%+.1f%%", signal.change))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(signal.change >= 0 ? .green : .red)
            }
            Divider()
            HStack {
                valueBlock("سعر الدخول وقت الفحص", p(signal.entry), color: .primary)
                Spacer()
                valueBlock("وقف الخسارة", p(signal.stop), color: .red)
            }
            HStack(spacing: 8) {
                ForEach(Array(signal.targets.enumerated()), id: \.offset) { i, target in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("الهدف \(i + 1) · \([3,5,8][i])R").font(.caption2).foregroundStyle(.secondary)
                        Text(p(target)).font(.subheadline.bold().monospacedDigit())
                        Text(String(format: "+%.1f%%", (target - signal.entry) / signal.entry * 100))
                            .font(.caption).foregroundStyle(.green)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack {
                Text("RSI \(String(format: "%.1f", signal.rsi))")
                Text("الحجم \(String(format: "%.2f", signal.volumeRatio))×")
                Text("المخاطرة \(String(format: "%.1f", signal.riskPct))%")
            }
            .font(.caption2).foregroundStyle(.secondary)

            Button(copied ? "تم النسخ" : "نسخ الإشارة") {
                UIPasteboard.general.string = model.copyText(for: signal)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { copied = false }
            }
            .buttonStyle(.bordered)
            .disabled(signal.isExpired)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func valueBlock(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(color)
            Text("USDT").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
