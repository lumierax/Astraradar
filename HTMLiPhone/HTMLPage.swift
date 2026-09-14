import SwiftUI
import UIKit
import WebKit

struct HTMLPage: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> HTMLPageController {
        HTMLPageController()
    }

    func updateUIViewController(
        _ controller: HTMLPageController,
        context: Context
    ) {
        // Keep the page and its JavaScript state across SwiftUI updates.
    }
}

final class HTMLPageController:
    UIViewController,
    WKNavigationDelegate,
    WKUIDelegate
{
    private var webView: WKWebView!
    private var hasStarted = false

    private let errorLabel = UILabel()
    private let errorStack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true

        webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(webView)

        let retryButton = UIButton(type: .system)
        retryButton.setTitle("إعادة المحاولة", for: .normal)
        retryButton.addTarget(
            self,
            action: #selector(loadPage),
            for: .touchUpInside
        )

        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        errorLabel.font = .preferredFont(forTextStyle: .body)
        errorLabel.adjustsFontForContentSizeCategory = true

        errorStack.axis = .vertical
        errorStack.spacing = 16
        errorStack.addArrangedSubview(errorLabel)
        errorStack.addArrangedSubview(retryButton)
        errorStack.translatesAutoresizingMaskIntoConstraints = false
        errorStack.isHidden = true

        view.addSubview(errorStack)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor
            ),
            webView.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor
            ),
            webView.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor
            ),
            webView.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor
            ),
            errorStack.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 24
            ),
            errorStack.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -24
            ),
            errorStack.centerYAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.centerYAnchor
            )
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !hasStarted {
            hasStarted = true
            loadPage()
        }
    }

    @objc private func loadPage() {
        guard let fileURL = Bundle.main.url(
            forResource: "index(20260914-180700)",
            withExtension: "html",
            subdirectory: "Web"
        ) else {
            showError("تعذّر العثور على ملف HTML داخل مجلد Web.")
            return
        }

        errorStack.isHidden = true
        webView.isHidden = false

        webView.loadFileURL(
            fileURL,
            allowingReadAccessTo: fileURL.deletingLastPathComponent()
        )
    }

    private func showError(_ message: String) {
        errorLabel.text = message
        errorStack.isHidden = false
        webView.isHidden = true
    }

    private func handleNavigationError(_ error: Error) {
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorCancelled {
            return
        }

        showError(error.localizedDescription)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationError(error)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationError(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        showError("توقف تشغيل الصفحة. اضغط إعادة المحاولة لفتحها مجددًا.")
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let internalSchemes = [
            "file", "http", "https", "about", "data", "blob", "javascript"
        ]

        if internalSchemes.contains(url.scheme?.lowercased() ?? "") {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)

            if navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(
                    url,
                    options: [:],
                    completionHandler: nil
                )
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }

        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(
            title: "رسالة من الصفحة",
            message: message,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(
            title: "حسنًا",
            style: .default
        ) { _ in
            completionHandler()
        })

        displayDialog(alert, fallback: completionHandler)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(
            title: "تأكيد من الصفحة",
            message: message,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(
            title: "إلغاء",
            style: .cancel
        ) { _ in
            completionHandler(false)
        })

        alert.addAction(UIAlertAction(
            title: "موافق",
            style: .default
        ) { _ in
            completionHandler(true)
        })

        displayDialog(alert) {
            completionHandler(false)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = UIAlertController(
            title: "إدخال من الصفحة",
            message: prompt,
            preferredStyle: .alert
        )

        alert.addTextField { field in
            field.text = defaultText
        }

        alert.addAction(UIAlertAction(
            title: "إلغاء",
            style: .cancel
        ) { _ in
            completionHandler(nil)
        })

        alert.addAction(UIAlertAction(
            title: "موافق",
            style: .default
        ) { [weak alert] _ in
            completionHandler(alert?.textFields?.first?.text ?? "")
        })

        displayDialog(alert) {
            completionHandler(nil)
        }
    }

    private func displayDialog(
        _ alert: UIAlertController,
        fallback: @escaping () -> Void
    ) {
        guard viewIfLoaded?.window != nil else {
            fallback()
            return
        }

        var presenter: UIViewController = self

        while let parent = presenter.parent {
            presenter = parent
        }

        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        if presenter.isBeingPresented || presenter.isBeingDismissed {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.25
            ) { [weak self] in
                guard let self = self else {
                    fallback()
                    return
                }

                self.displayDialog(alert, fallback: fallback)
            }
            return
        }

        presenter.present(alert, animated: true)
    }
}
