import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ExcludedAppsView: View {
    @ObservedObject var inputManager: InputSourceManager
    @State private var selection: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Choose what TypeLock should do in specific apps.")
                    .font(.headline)
                Text("An input method overrides your default. Choose “Don’t Enforce” to let an app manage itself.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            Group {
                if inputManager.excludedApps.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("No App Rules")
                            .font(.headline)
                        Text("Add an app to assign an input method or leave it unmanaged.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(32)
                } else {
                    List(inputManager.excludedApps, selection: $selection) { app in
                        HStack(spacing: 12) {
                            AppIconView(bundleID: app.bundleID)
                                .frame(width: 28, height: 28)

                            Text(app.name)
                                .fontWeight(.medium)
                                .lineLimit(1)

                            Spacer(minLength: 16)

                            Picker("Input method for \(app.name)", selection: inputSourceBinding(for: app.bundleID)) {
                                Text("Don’t Enforce").tag("")
                                Divider()
                                ForEach(inputManager.availableSources, id: \.id) { source in
                                    Text(source.name).tag(source.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 190, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                        .tag(app.bundleID)
                        .contextMenu {
                            Button("Remove Rule", role: .destructive) {
                                removeApp(bundleID: app.bundleID)
                            }
                        }
                    }
                    .listStyle(InsetListStyle())
                    .onDeleteCommand(perform: removeSelected)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button(action: addApps) {
                    Label("Add App…", systemImage: "plus")
                }
                .help("Add an app rule")

                Button(action: removeSelected) {
                    Label("Remove", systemImage: "minus")
                }
                .disabled(selection.isEmpty)
                .help("Remove the selected app rules")

                Spacer()

                Text(appCountLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 500, minHeight: 340)
    }

    private var appCountLabel: String {
        let count = inputManager.excludedApps.count
        return "\(count) \(count == 1 ? "app" : "apps")"
    }

    private func inputSourceBinding(for bundleID: String) -> Binding<String> {
        Binding(
            get: {
                inputManager.excludedApps.first(where: { $0.bundleID == bundleID })?.inputSourceID ?? ""
            },
            set: { newValue in
                inputManager.updateExcludedApp(bundleID: bundleID, inputSourceID: newValue.isEmpty ? nil : newValue)
            }
        )
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.title = "Add App Rule"
        panel.message = "Choose one or more apps for TypeLock to manage differently."
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            guard let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            inputManager.addExcludedApp(bundleID: bundleID, name: name)
        }
    }

    private func removeSelected() {
        for bundleID in selection {
            inputManager.removeExcludedApp(bundleID: bundleID)
        }
        selection.removeAll()
    }

    private func removeApp(bundleID: String) {
        inputManager.removeExcludedApp(bundleID: bundleID)
        selection.remove(bundleID)
    }
}

struct AppIconView: NSViewRepresentable {
    let bundleID: String

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setAccessibilityElement(false)
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            nsView.image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            nsView.image = NSImage(systemSymbolName: "app", accessibilityDescription: nil)
        }
    }
}
