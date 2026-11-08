import SwiftUI

struct StatusPanelView: View {
    static let size = NSSize(width: 406, height: 488)
    private static let repositoryURL = URL(string: "https://github.com/Evenss/Bilby")!
    private static let githubIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "GitHubLink", withExtension: "pdf"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()
    let model: AppModel
    let close: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(nsImage: BrandIcon.menuBarImage())
                    .renderingMode(.template)
                    .accessibilityHidden(true)
                Text(BrandIcon.name).font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 48)

            LayoutView(model: model)

            HStack {
                Button {
                    close()
                    NSWorkspace.shared.open(Self.repositoryURL)
                } label: {
                    Group {
                        if let icon = Self.githubIcon {
                            Image(nsImage: icon)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                        } else {
                            Text("GitHub")
                        }
                    }
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("打开 GitHub 仓库")
                .accessibilityLabel("打开 Bilby 的 GitHub 仓库")
                .accessibilityIdentifier("Bilby.GitHub")
                Spacer()
                Button("退出", action: quit)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                    .keyboardShortcut("q", modifiers: .command)
                    .help("退出 Bilby 并恢复所有图标")
                    .accessibilityIdentifier("Bilby.Quit")
            }
            .padding(.horizontal, 26)
            .frame(height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PanelMaterial()
                .overlay(Color(red: 0.105, green: 0.11, blue: 0.13).opacity(0.76))
                .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onExitCommand(perform: close)
    }
}

private struct PanelMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
