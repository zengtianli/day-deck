import SwiftUI
import UniformTypeIdentifiers

/// Product actions are shared by the visible controls and the in-process acceptance entry.
/// The shared modules own configuration merging, validation, backups and release parsing.
@MainActor
final class ProductSettingsModel: ObservableObject {
    let configuration: AppConfiguration
    let file: URL
    @Published var startupTab: Int
    @Published var status = ""
    @Published var cloudEnabled: Bool
    @Published var updateStatus = "尚未检查；内测版本仍由 TestFlight 安装。"
    @Published var checking = false
    @Published var release: AppRelease?
    @Published var notice: String?
    @Published var closed = false
    typealias Request = (@escaping (Result<AppRelease, Error>) -> Void) -> Void
    private let request: Request
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未标明"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未标明"
    static let pages = ["今天", "通知", "随手记", "连接"]
    static let storeURL = URL(string: "https://apps.apple.com/app/id6807048407")!
    static let betaURL = URL(string: "itms-beta://")!

    init(configuration: AppConfiguration = MobileProductLifecycle.configuration,
         file: URL = MobileProductLifecycle.preferencesURL, request: Request? = nil) {
        self.configuration = configuration; self.file = file
        startupTab = MobileProductLifecycle.readStartupTab(from: file)
        cloudEnabled = configuration.enabled
        self.request = request ?? { completion in
            AppUpdateChecker.check(source: .appStore(id: MobileProductLifecycle.storeID),
                bundleID: Bundle.main.bundleIdentifier ?? "", version: "", build: "", completion: completion)
        }
    }
    func refresh() {
        startupTab = MobileProductLifecycle.readStartupTab(from: file)
        cloudEnabled = configuration.enabled; status = configuration.status
    }
    func selectPage(_ tab: Int) {
        do {
            guard (0...3).contains(tab) else { throw AppUpdateError("无效的启动页面；原配置已保留。") }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["startupTab": tab], options: [.sortedKeys]).write(to: file, options: .atomic)
            refresh()
            if configuration.enabled { configuration.reconcile() }
        } catch { notice = error.localizedDescription }
    }
    func setCloud(_ enabled: Bool) { configuration.setEnabled(enabled); refresh() }
    func exportConfiguration() throws -> Data { try configuration.exportData() }
    func importConfiguration(_ data: Data) {
        do { try configuration.importData(data); refresh(); notice = "配置已导入；原配置已备份。" }
        catch { notice = "导入未完成：\(error.localizedDescription)" }
    }
    func checkUpdates() {
        guard !checking else { return }
        checking = true; updateStatus = "正在检查 App Store…"
        request { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.checking = false
                switch result {
                case .success(let release):
                    self.release = release
                    self.updateStatus = release.isNewer(than: self.version, build: self.build)
                        ? "发现商店版本 \(release.version)。" : "商店版本 \(release.version)；已安装 \(self.version) (\(self.build))。"
                case .failure(let error):
                    self.release = nil
                    self.updateStatus = "检查未完成：\(error.localizedDescription) 内测用户请在 TestFlight 查看版本。"
                }
            }
        }
    }
    func openUpdate(_ url: URL, using open: (URL, @escaping (Bool) -> Void) -> Void) {
        open(url) { [weak self] accepted in
            if !accepted { self?.notice = "系统未能打开更新入口；请在 App Store 或 TestFlight 中打开 Notihub。" }
        }
    }
    func close() { closed = true }
}

struct ProductSettingsPanel: View {
    @ObservedObject var model: ProductSettingsModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var importing = false
    @State private var exporting = false
    @State private var document = AppConfigurationDocument()

    var body: some View {
        NavigationStack {
            Form {
                Section("使用偏好") {
                    Picker("启动页面", selection: Binding(get: { model.startupTab }, set: model.selectPage)) {
                        ForEach(0..<4) { Text(ProductSettingsModel.pages[$0]).tag($0) }
                    }.accessibilityIdentifier("settings.startupPage")
                    Text("下次打开 App 时使用；不会改变当前页面。")
                }
                Section("iCloud 配置") {
                    Toggle("使用 iCloud 记住配置", isOn: Binding(get: { model.cloudEnabled }, set: model.setCloud))
                        .accessibilityIdentifier("configuration.iCloud")
                    Text(model.status).font(.footnote)
                    Text("默认关闭，只同步启动页面。账号、密码、随手记草稿、缓存、提醒列表与权限不参与；关闭保留本机配置。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("导出配置…") {
                        do { document = AppConfigurationDocument(data: try model.exportConfiguration()); exporting = true }
                        catch { model.notice = error.localizedDescription }
                    }
                    Button("导入配置…") { importing = true }
                }
                Section("应用版本") {
                    LabeledContent("已安装", value: "\(model.version) (\(model.build))")
                    Text(model.updateStatus).font(.footnote)
                    Button(model.checking ? "正在检查…" : "检查 App Store 更新", action: model.checkUpdates).disabled(model.checking)
                    Button("前往 App Store") { open(ProductSettingsModel.storeURL) }
                    Button("在 TestFlight 查看内测更新") { open(ProductSettingsModel.betaURL) }
                    Text("更新由 Apple 安装，不替换本机配置或草稿；商店尚未发行时会明确提示。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("操作方式") {
                    Text("iPhone / iPad 使用触屏标签页、搜索和按钮；没有全局键盘监听或呼出快捷键。输入框保留系统编辑操作。")
                        .font(.footnote)
                }
            }.navigationTitle("设置与更新")
                .toolbar { ToolbarItem { Button("完成") { model.close(); dismiss() } } }
        }
        .onAppear { model.configuration.start(); model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AppConfigurationStatusChanged"), object: model.configuration)) { _ in model.refresh() }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "notihub-config") { result in
            if case .failure(let error) = result { model.notice = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(), scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 <= 4 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                model.importConfiguration(try Data(contentsOf: url))
            } catch { model.notice = error.localizedDescription }
        }
        .alert("设置与更新", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("好") { model.notice = nil }
        } message: { Text(model.notice ?? "") }
    }
    private func open(_ url: URL) {
        model.openUpdate(url) { url, completion in openURL(url, completion: completion) }
    }
}

struct ProductSettingsEntry: View {
    @EnvironmentObject private var lifecycle: MobileLifecycleModel
    @StateObject private var model = ProductSettingsModel()
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: { Label("设置与更新", systemImage: "gearshape") }
            // Reuse the shared fixture boundary: demo/guide launches cannot change real settings.
            .disabled(lifecycle.configuration == nil)
            .sheet(isPresented: $showing) { ProductSettingsPanel(model: model) }
    }
}
