import SwiftUI
import AppKit
import WebKit

public enum RoutinePage: String, Codable, CaseIterable, Sendable {
    case workout, today, timetable
    public var title: String {
        switch self { case .workout: return "Scheda palestra"; case .today: return "Planning di oggi"; case .timetable: return "Orario lezioni" }
    }
    var navigationLabel: String {
        switch self { case .workout: return "Scheda"; case .today: return "Oggi"; case .timetable: return "Esami" }
    }
}
public struct RoutinePreferences: Codable, Equatable, Sendable {
    public var page: RoutinePage = .workout
    public var zoom = 0.9
    public init() {}
}

/// The actual Routine application: its IndexedDB queue and authenticated Supabase
/// sync handle edits in both directions. No second workout model or copied plan.
public struct SharedRoutineWidget: View {
    @ObservedObject private var channel: SharedWidgetChannel<RoutinePreferences>
    @StateObject private var session = RoutineWebSession()
    @State private var flipped = false
    @State private var draft = RoutinePreferences()
    private let isEditing: Bool
    private let pageOverride: RoutinePage?
    private var displayPage: RoutinePage { pageOverride ?? channel.value.page }
    public init(library: SharedWidgetLibrary? = nil, isEditing: Bool = false, page: RoutinePage? = nil) {
        channel = (library ?? .shared).routine; self.isEditing = isEditing; pageOverride = page
    }
    public var body: some View {
        WidgetFlipCard(title: "Routine · Palestra", symbol: "dumbbell", flipped: $flipped, isEditing: isEditing,
                       onEdit: { draft = channel.value; flipped = true },
                       onSave: { try channel.update { $0 = draft } }) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "dumbbell.fill").foregroundStyle(.orange)
                    Text(displayPage.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer()
                    if session.loading { ProgressView().controlSize(.small) }
                    Button { session.navigate(displayPage) } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).help("Aggiorna Routine")
                    Button { NSWorkspace.shared.open(RoutineWebSession.url) } label: { Image(systemName: "arrow.up.right.square") }
                        .buttonStyle(.plain).help("Apri Routine nel browser")
                    Color.clear.frame(width: 28, height: 26)
                }.padding(.horizontal, 14).padding(.vertical, 12)
                if let error = session.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark").font(.title)
                        Text(error).font(.caption).multilineTextAlignment(.center)
                        Button("Riprova") { session.load() }
                    }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    RoutineBrowser(session: session).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .foregroundStyle(.white).background(Color(red: 0.055, green: 0.055, blue: 0.07))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        } settings: {
            VStack(alignment: .leading, spacing: 12) {
                if pageOverride == nil {
                    Picker("Mostra", selection: $draft.page) {
                        ForEach(RoutinePage.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Text("Dimensione del contenuto: \(Int(draft.zoom * 100))%")
                Slider(value: $draft.zoom, in: 0.7...1.2, step: 0.05)
                Text("Accedi nel widget con lo stesso account di Routine. Scheda, esercizi e registrazioni usano il suo archivio Supabase. Le modifiche offline si sincronizzano quando torna la rete; con entrambe aperte possono richiedere circa un minuto.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Qui trovi la scheda già configurata in Routine. Il PDF originale non viene convertito automaticamente in esercizi.")
                    .font(.caption2).foregroundStyle(.secondary)
                Button("Apri Routine nel browser") { NSWorkspace.shared.open(RoutineWebSession.url) }
            }.font(.system(size: 12))
        }
        .onAppear { session.page = displayPage; session.webView.pageZoom = channel.value.zoom; session.loadIfNeeded() }
        .onChange(of: channel.value) { _, value in
            session.webView.pageZoom = min(1.2, max(0.7, value.zoom)); session.navigate(pageOverride ?? value.page)
        }
    }
}

@MainActor final class RoutineWebSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    static let url = URL(string: "https://tracking-daily.vercel.app")!
    let webView: WKWebView
    @Published var loading = false
    @Published var errorMessage: String?
    var page: RoutinePage = .workout
    private var started = false
    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.appearance = NSAppearance(named: .darkAqua)
        webView.underPageBackgroundColor = NSColor(white: 0.055, alpha: 1)
    }
    func loadIfNeeded() { if !started { load() } }
    func load() { started = true; loading = true; errorMessage = nil; webView.load(URLRequest(url: Self.url)) }
    func navigate(_ page: RoutinePage) {
        self.page = page
        if !started || errorMessage != nil { load(); return }
        guard !webView.isLoading else { return }
        applyPage()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false; errorMessage = nil; applyPage() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    private func fail(_ error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        loading = false; errorMessage = "Routine non è raggiungibile. Controlla la connessione e riprova."
    }
    private func applyPage() {
        // Navigation labels are from Routine's own App.tsx. Keep the real app's
        // controls and persistence; do not inject or read authentication tokens.
        let label = page.navigationLabel
        let isTimetable = page == .timetable
        let script = """
        (() => {
          if (location.origin !== 'https://tracking-daily.vercel.app') return;
          window.__routineWidgetObserver?.disconnect();
          let chosen = false;
          const choose = () => {
            if (!chosen) {
              const button = [...document.querySelectorAll('nav button, aside button')].find(b => b.textContent.trim() === '\(label)');
              if (!button) return;
              chosen = true; button.click();
            }
            if (\(isTimetable ? "true" : "false")) {
              const heading = [...document.querySelectorAll('h2')].find(h => h.textContent.trim() === 'Orario settimanale');
              if (!heading) return;
              heading.closest('section')?.scrollIntoView({block:'start'});
            }
            window.__routineWidgetObserver?.disconnect();
          };
          window.__routineWidgetObserver = new MutationObserver(choose);
          window.__routineWidgetObserver.observe(document.body, {childList:true, subtree:true});
          choose();
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.host == Self.url.host, url.scheme == "https" { decisionHandler(.allow) }
        else if url.scheme == "about" || url.scheme == "blob" { decisionHandler(.allow) }
        else { decisionHandler(.cancel); if navigationAction.navigationType == .linkActivated { NSWorkspace.shared.open(url) } }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert(); alert.messageText = message; alert.addButton(withTitle: "Conferma"); alert.addButton(withTitle: "Annulla")
        if let window = webView.window { alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) } }
        else { completionHandler(alert.runModal() == .alertFirstButtonReturn) }
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        if let window = webView.window { panel.beginSheetModal(for: window) { completionHandler($0 == .OK ? panel.urls : nil) } }
        else { completionHandler(panel.runModal() == .OK ? panel.urls : nil) }
    }
}
private struct RoutineBrowser: NSViewRepresentable {
    let session: RoutineWebSession
    func makeNSView(context: Context) -> WKWebView { session.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
