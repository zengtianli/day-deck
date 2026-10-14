#if DEBUG && os(iOS)
import SwiftUI
import UIKit

struct ProductBasicsTestView: View {
    var body: some View { Color.clear.task { await ProductBasicsSelfTest.run() } }
}

/// Runs only inside the real simulator App. No events, key window, account or production API.
@MainActor
enum ProductBasicsSelfTest {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("--ui-self-test") }
    static func run() async {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--ui-self-test"), args.indices.contains(i + 1) else { exit(2) }
        let phase = args[i + 1]
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("product-basics")
        var checks: [String: Bool] = [:]
        var observations: [String: Any] = [:]
        do {
            let device = phase == "remote" ? "B" : "A"
            let local = root.appendingPathComponent(device)
            let file = local.appendingPathComponent("preferences.json")
            let cloud = root.appendingPathComponent("cloud")
            try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
            setenv("APP_LIFECYCLE_SUPPORT_DIR", local.appendingPathComponent("support").path, 1)
            setenv("APP_LIFECYCLE_CLOUD_DIR", cloud.path, 1)
            let defaults = UserDefaults(suiteName: "test.notihub.product-basics." + device)!
            let config = MobileProductLifecycle.makeConfiguration(defaults: defaults, file: file)
            let model = ProductSettingsModel(configuration: config, file: file)
            let remote = cloud.appendingPathComponent("day-deck.json")
            func saved() -> Data? { try? Data(contentsOf: file) }
            func settle() async -> Bool {
                await withCheckedContinuation { continuation in
                    config.reconcile { error in continuation.resume(returning: error == nil) }
                }
            }
            switch phase {
            case "seed":
                model.selectPage(2)
                checks["settings.control_saved"] = model.startupTab == 2 && saved() != nil
                let original = saved()
                model.selectPage(99)
                checks["settings.invalid_selection_preserved"] = saved() == original && model.notice != nil
                model.notice = nil
                let export = try model.exportConfiguration()
                try export.write(to: root.appendingPathComponent("export.json"))
                model.selectPage(1)
                model.importConfiguration(export)
                checks["settings.export_import"] = model.startupTab == 2 && model.notice?.contains("备份") == true
                let imported = saved()
                model.importConfiguration(Data("{broken".utf8))
                checks["settings.malformed_preserved"] = saved() == imported && model.notice?.contains("未完成") == true
                let invalid = Data("{\"version\":1,\"product\":\"day-deck\",\"values\":{\"file.0.startupTab\":99}}".utf8)
                model.importConfiguration(invalid)
                checks["settings.invalid_import_preserved"] = saved() == imported
                defaults.set("PRIVATE-DRAFT", forKey: "diary.cloudDraft.text")
                defaults.set("PRIVATE-TOKEN", forKey: "credential")
                let envelope = String(decoding: try model.exportConfiguration(), as: UTF8.self)
                checks["icloud.allowlist_excludes_private_data"] = !envelope.contains("PRIVATE") && !envelope.contains("diary") && envelope.contains("startupTab")
                model.notice = nil
                try await snapshot(model, to: root.appendingPathComponent("settings.png"))
                checks["settings.offscreen_view_rendered"] = FileManager.default.fileExists(atPath: root.appendingPathComponent("settings.png").path)
                model.close()
                checks["settings.close_action"] = model.closed
                model.setCloud(true)
                checks["icloud.push"] = await settle()
                checks["icloud.cloud_file_written"] = FileManager.default.fileExists(atPath: remote.path)
            case "readback":
                checks["settings.fresh_process_readback"] = model.startupTab == 2 && MobileProductLifecycle.readStartupTab(from: file) == 2
                checks["icloud.enabled_persisted"] = model.cloudEnabled
            case "remote":
                checks["icloud.fresh_device_was_empty"] = saved() == nil
                model.setCloud(true)
                checks["icloud.fresh_device_pull"] = await settle()
                model.refresh()
                checks["icloud.empty_device_does_not_overwrite"] = model.startupTab == 2
                model.selectPage(1)
                checks["icloud.second_device_push"] = await settle()
            case "receive":
                checks["icloud.receive_reconcile"] = await settle()
                model.refresh()
                checks["icloud.remote_change_applied"] = model.startupTab == 1
            case "fallback":
                unsetenv("APP_LIFECYCLE_CLOUD_DIR")
                let before = saved()
                checks["icloud.unavailable_reports_error"] = !(await settle())
                checks["icloud.unavailable_preserves_file"] = before == saved()
                model.selectPage(3)
                let offlineExport = try model.exportConfiguration()
                checks["icloud.offline_local_write"] = model.startupTab == 3 && offlineExport.count > 0
                observations["status"] = config.status
            case "corrupt":
                let before = saved()
                try Data(contentsOf: remote).write(to: root.appendingPathComponent("cloud-backup.json"))
                try Data("{broken".utf8).write(to: remote, options: .atomic)
                checks["icloud.corrupt_reports_error"] = !(await settle())
                checks["icloud.corrupt_preserves_local"] = saved() == before
            case "recover":
                var restored = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("cloud-backup.json"))) as! [String: Any]
                var values = restored["values"] as! [String: Any]
                // Both clients changed the same preference since A's baseline (1): local=3, remote=2.
                values["file.0.startupTab"] = 2; restored["values"] = values
                try JSONSerialization.data(withJSONObject: restored).write(to: remote, options: .atomic)
                checks["icloud.remote_conflict_was_distinct"] = model.startupTab == 3 && values["file.0.startupTab"] as? Int == 2
                checks["icloud.recovery_reconcile"] = await settle()
                model.refresh()
                checks["icloud.offline_edit_wins_conflict"] = model.startupTab == 3
                let object = try JSONSerialization.jsonObject(with: Data(contentsOf: remote)) as? [String: Any]
                checks["icloud.merged_cloud_readback"] = (object?["values"] as? [String: Any])?["file.0.startupTab"] as? Int == 3
            case "disable":
                let before = try Data(contentsOf: remote)
                let localBefore = saved()
                model.setCloud(false)
                checks["icloud.disable_keeps_existing_local"] = saved() == localBefore && !config.enabled
                model.selectPage(0)
                _ = await settle()
                checks["icloud.disable_keeps_cloud"] = try Data(contentsOf: remote) == before
                checks["icloud.disabled_local_usable"] = model.startupTab == 0
            case "updates":
                let before = saved(), cloudBefore = try Data(contentsOf: remote)
                let source = root.appendingPathComponent("store-fixture.json")
                let request: ProductSettingsModel.Request = { done in
                    // Actual isolated version source, read on every click; shared production parser.
                    done(Result { try AppUpdateChecker.appStore(Data(contentsOf: source), id: MobileProductLifecycle.storeID,
                                                               bundleID: Bundle.main.bundleIdentifier ?? "") })
                }
                let update = ProductSettingsModel(configuration: config, file: file, request: request)
                func check(_ model: ProductSettingsModel) async -> Bool {
                    model.checkUpdates()
                    for _ in 0..<250 {
                        if !model.checking { return true }
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    return false
                }
                try Data("{broken".utf8).write(to: source)
                let failed = await check(update)
                checks["updates.bad_source_reported"] = failed && update.release == nil && update.updateStatus.contains("未完成")
                let response: [String: Any] = ["resultCount": 1, "results": [["trackId": 6807048407, "bundleId": Bundle.main.bundleIdentifier ?? "", "version": "99.0", "trackViewUrl": ProductSettingsModel.storeURL.absoluteString]]]
                try JSONSerialization.data(withJSONObject: response).write(to: source, options: .atomic)
                let recovered = await check(update)
                checks["updates.fixture_version_read"] = recovered && update.release?.version == "99.0" && update.updateStatus.contains("99.0")
                var opened: [String] = []
                update.openUpdate(ProductSettingsModel.storeURL) { url, done in opened.append(url.absoluteString); done(false) }
                checks["updates.open_failure_reported"] = update.notice != nil
                update.notice = nil
                update.openUpdate(ProductSettingsModel.storeURL) { url, done in opened.append(url.absoluteString); done(true) }
                update.openUpdate(ProductSettingsModel.betaURL) { url, done in opened.append(url.absoluteString); done(true) }
                checks["updates.store_and_beta_entry_actions"] = Array(opened.suffix(2)) == [ProductSettingsModel.storeURL.absoluteString, "itms-beta://"] && update.notice == nil
                let live = ProductSettingsModel(configuration: config, file: file)
                let finished = await check(live)
                checks["updates.actual_apple_request_completed"] = finished && (live.release != nil || live.updateStatus.contains("检查未完成"))
                observations["actual_store_status"] = live.updateStatus
                observations["actual_store_version"] = (live.release?.version as Any?) ?? NSNull()
                let cloudAfter = try Data(contentsOf: remote)
                checks["updates.checks_preserve_configuration"] = saved() == before && cloudAfter == cloudBefore
                checks["updates.checks_preserve_private_draft"] = defaults.string(forKey: "diary.cloudDraft.text") == "PRIVATE-DRAFT"
                checks["updates.synchronization_stays_disabled"] = !config.enabled
                try await snapshot(update, to: root.appendingPathComponent("updates.png"))
            default: throw AppUpdateError("Unknown self-test phase")
            }
            observations["startup_page"] = model.startupTab
            observations["cloud_enabled"] = config.enabled
            observations["bundle_id"] = Bundle.main.bundleIdentifier ?? ""
            observations["version"] = model.version
            observations["build"] = model.build
        } catch { checks["phase.completed"] = false; observations["error"] = error.localizedDescription }
        let record: [String: Any] = ["phase": phase, "checks": checks, "observations": observations,
                                     "environment": "simulator", "process_id": ProcessInfo.processInfo.processIdentifier]
        let data = try! JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: root.appendingPathComponent(phase + ".json"), options: .atomic)
        exit(checks.values.allSatisfy { $0 } && !checks.isEmpty ? 0 : 1)
    }

    private static func snapshot(_ model: ProductSettingsModel, to file: URL) async throws {
        let controller = UIHostingController(rootView: ProductSettingsPanel(model: model).preferredColorScheme(.light))
        let window = UIWindow(frame: CGRect(x: -10000, y: -10000, width: 430, height: 1100))
        window.rootViewController = controller
        // A non-key window outside the simulated screen lets UIKit materialize Form cells.
        // Simulator.app is never opened; this window cannot take host or simulator input focus.
        window.isHidden = false
        defer { window.isHidden = true }
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
        controller.view.frame = CGRect(x: 0, y: 0, width: 430, height: 1100)
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: controller.view.bounds.size).image { context in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        guard let png = image.pngData(), png.count > 10000, window.frame.maxX < 0, !window.isKeyWindow else {
            throw AppUpdateError("真实设置视图离屏渲染失败")
        }
        try png.write(to: file)
    }
}
#endif
