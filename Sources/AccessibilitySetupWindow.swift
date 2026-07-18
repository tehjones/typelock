import AppKit
import SwiftUI

final class AccessibilitySetupWindowController: NSWindowController {
    private let hostingController: NSHostingController<AccessibilitySetupView>

    init(view: AccessibilitySetupView) {
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Set Up TypeLock"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 380))
        window.center()

        self.hostingController = hostingController
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(view: AccessibilitySetupView) {
        hostingController.rootView = view
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct AccessibilitySetupView: View {
    let isAllowed: Bool
    let onRequestAccessibility: () -> Void
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            Text("Allow TypeLock to switch automatically")
                .font(.title2.weight(.semibold))
                .padding(.top, 14)

            Text("TypeLock uses Accessibility to see which app is active and apply the right input method.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
                .padding(.top, 6)

            PermissionCard(
                isAllowed: isAllowed,
                onAllow: onRequestAccessibility
            )
            .padding(.top, 26)

            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 18)

            Spacer(minLength: 22)

            Divider()

            HStack {
                if !isAllowed {
                    Button("Not Now", action: onClose)
                        .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button("Open System Settings…", action: onOpenSettings)
                } else {
                    Spacer()
                }

                if isAllowed {
                    Button("Done", action: onClose)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, 16)
        }
        .padding(30)
        .frame(width: 520, height: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusMessage: String {
        if isAllowed {
            return "TypeLock is ready. Choose an input method from the menu bar."
        }
        return "Click Allow to add TypeLock. It never reads or records what you type."
    }
}

private struct PermissionCard: View {
    let isAllowed: Bool
    let onAllow: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "accessibility")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Accessibility")
                    .font(.headline)
                Text("See which app is active and apply its input method rule.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            if isAllowed {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Button("Allow…", action: onAllow)
                    .accessibilityLabel("Allow Accessibility")
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}
