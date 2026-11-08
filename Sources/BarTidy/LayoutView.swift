import SwiftUI
import BarTidyCore

struct LayoutView: View {
    @Bindable var model: AppModel
    @State private var presentation: LayoutProfile
    @State private var pendingCount = 0
    @State private var queuedUpdate: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
        _presentation = State(initialValue: model.draft)
    }

    var body: some View {
        Group {
            if !model.hasPermission { permission }
            else if model.managedApps.isEmpty { emptyState }
            else { settings }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.draft, initial: true) { _, _ in syncPresentation() }
        .onChange(of: model.managedApps.map { $0.identity.bundleID }.sorted(), initial: true) { _, _ in syncPresentation() }
        .alert("未能完成操作", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("知道了") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var settings: some View {
        Form {
            if !shownRows.isEmpty {
                Section {
                    ForEach(shownRows, id: \.identity.bundleID) { item in appRow(item) }
                } header: {
                    sectionHeader(model.isRevealed ? "临时显示中" : "显示中", count: shownRows.count)
                }
            }
            if !otherRows.isEmpty {
                Section {
                    ForEach(otherRows, id: \.identity.bundleID) { item in appRow(item) }
                } header: {
                    sectionHeader("已隐藏", count: otherRows.count)
                }
            }
        }
        .formStyle(SoftGroupedFormStyle())
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 11, weight: .medium))
            Text("\(count)").font(.system(size: 11)).monospacedDigit()
        }
        .foregroundStyle(.secondary)
    }

    private func appRow(_ item: MenuBarItem) -> some View {
        Toggle(isOn: Binding(
            get: { isShown(item) },
            set: { show in changeVisibility(item.identity.bundleID, show: show) }
        )) {
            HStack(spacing: 12) {
                Image(nsImage: icon(item)).resizable().scaledToFit()
                    .frame(width: 24, height: 24).accessibilityHidden(true)
                Text(item.identity.name).font(.system(size: 13)).lineLimit(1)
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .accessibilityLabel("\(item.identity.name)，在状态栏显示")
        .accessibilityIdentifier("visibility.\(item.identity.bundleID)")
        // Pending saves never disable the rest of the form.
        .disabled(model.isBusy && pendingCount == 0)
        // Cross-section identity changes remove and insert a row. Keep that
        // replacement immediate; a fading old copy can overlap the new header.
        .transition(.identity)
    }

    private var orderedRows: [MenuBarItem] {
        let apps = model.managedApps
        let byBundle = Dictionary(apps.map { ($0.identity.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        return presentation.displayedApps(apps.map(\.identity)).compactMap { byBundle[$0.bundleID] }
    }

    private var shownRows: [MenuBarItem] { orderedRows.filter { isShown($0) } }
    private var otherRows: [MenuBarItem] { orderedRows.filter { !isShown($0) } }

    private func isShown(_ item: MenuBarItem) -> Bool {
        model.isRevealed || !presentation.hiddenBundles.contains(item.identity.bundleID)
    }

    private func syncPresentation() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if pendingCount == 0 { presentation = model.draft }
            presentation.registerDisplayApps(model.managedApps.map { $0.identity.bundleID })
        }
    }

    private func changeVisibility(_ bundleID: String, show: Bool) {
        let predecessor = queuedUpdate
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if show { presentation.hiddenBundles.remove(bundleID) }
            else { presentation.hiddenBundles.insert(bundleID) }
            presentation.appendDisplayApp(bundleID)
            pendingCount += 1
        }
        queuedUpdate = Task { @MainActor in
            await predecessor?.value
            // Presentation already reflects the latest intent. Native updates
            // and saves remain serialized, with rollback after a failed save.
            await model.setHidden(bundleID, hidden: !show)
            pendingCount -= 1
            if pendingCount == 0 {
                queuedUpdate = nil
                syncPresentation()
            }
        }
    }

    private var emptyState: some View {
        Group {
            if model.isBusy { ProgressView("正在读取状态栏…") }
            else {
                ContentUnavailableView("暂未发现可管理的应用", systemImage: "menubar.rectangle",
                                       description: Text("打开带有状态栏图标的应用后，会自动显示在这里。"))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permission: some View {
        VStack(spacing: 18) {
            Image(systemName: "hand.raised.circle").font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
            Text("允许读取状态栏").font(.title3.weight(.semibold))
            Text("在系统设置中为 Bilby 开启辅助功能。")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("打开辅助功能设置") { model.requestPermission() }.buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
    }

    private func icon(_ item: MenuBarItem) -> NSImage {
        item.appURL.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
    }
}
