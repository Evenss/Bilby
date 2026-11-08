import SwiftUI
import BarTidyCore

struct LayoutView: View {
    @Bindable var model: AppModel
    let close: () -> Void
    @State private var presentation: LayoutProfile
    @State private var pendingCount = 0
    @State private var queuedUpdate: Task<Void, Never>?

    init(model: AppModel, close: @escaping () -> Void) {
        self.model = model
        self.close = close
        _presentation = State(initialValue: model.draft)
    }

    var body: some View {
        Group {
            if model.installation != .installed { installation }
            else if !model.hasPermission { permission }
            else if model.managedApps.isEmpty { emptyState }
            else { settings }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.draft, initial: true) { _, _ in syncPresentation() }
        .onChange(of: model.managedApps.map { $0.identity.bundleID }.sorted(), initial: true) { _, _ in syncPresentation() }
        .alert(L10n.text("Couldn't complete the action"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(L10n.text("OK")) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var settings: some View {
        Form {
            if !shownRows.isEmpty {
                Section {
                    ForEach(shownRows, id: \.identity.bundleID) { item in appRow(item) }
                } header: {
                    sectionHeader(model.isRevealed ? L10n.text("Temporarily visible") : L10n.text("Visible"), count: shownRows.count)
                }
            }
            if !otherRows.isEmpty {
                Section {
                    ForEach(otherRows, id: \.identity.bundleID) { item in appRow(item) }
                } header: {
                    sectionHeader(L10n.text("Hidden"), count: otherRows.count)
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
                if model.unconfirmedBundles.contains(item.identity.bundleID) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                        .help(L10n.text("The icon is still visible. Your preference is saved."))
                        .accessibilityLabel(L10n.text("Hiding has not taken effect"))
                }
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .accessibilityLabel(L10n.format("Show %@ in the menu bar", item.identity.name))
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
            if model.isLoading || model.isWaitingForInventory {
                ProgressView(model.isWaitingForInventory ? L10n.text("Waiting for the menu bar…") : L10n.text("Reading the menu bar…"))
            }
            else {
                ContentUnavailableView(L10n.text("No apps to manage yet"), systemImage: "menubar.rectangle",
                                       description: Text(L10n.text("Apps with menu bar icons will appear here.")))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permission: some View {
        VStack(spacing: 18) {
            Image(systemName: "hand.raised.circle").font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
            Text(model.permissionWasGranted ? L10n.text("Restore Accessibility access") : L10n.text("Allow Accessibility access")).font(.title3.weight(.semibold))
            Text(model.permissionWasGranted ? L10n.text("Your choices are saved. Re-enable Bilby in System Settings. If access still fails after an update, remove its old entry and add Bilby from Applications again.") : L10n.text("Enable Bilby in Privacy & Security → Accessibility. If Bilby isn't listed, use + to add it from Applications."))
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(L10n.text("Open Accessibility Settings")) { close(); model.requestPermission() }.buttonStyle(.borderedProminent)
            Button(L10n.text("Show Bilby in Finder")) { close(); model.showInFinder() }.buttonStyle(.link)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
    }

    private var installation: some View {
        VStack(spacing: 18) {
            Image(systemName: "arrow.down.app").font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
            Text(L10n.text("Install Bilby first")).font(.title3.weight(.semibold))
            Text(L10n.text("Move Bilby to Applications, then open it there and allow Accessibility access."))
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(L10n.text("Show Bilby in Finder")) { close(); model.showInFinder() }.buttonStyle(.borderedProminent)
            Button(L10n.text("Open Applications Folder")) { close(); model.openApplicationsFolder() }.buttonStyle(.link)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
    }

    private func icon(_ item: MenuBarItem) -> NSImage {
        item.appURL.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
    }
}
