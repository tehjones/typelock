import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ExcludedAppsView: View {
    @ObservedObject var inputManager: InputSourceManager
    @State private var selection: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apps listed here are excluded from the global lock. Optionally, assign an input method to switch to automatically when the app activates.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(inputManager.excludedApps, selection: $selection) { app in
                HStack(spacing: 8) {
                    AppIconView(bundleID: app.bundleID)
                        .frame(width: 20, height: 20)
                    Text(app.name)
                    Spacer()
                    Picker("", selection: inputSourceBinding(for: app.bundleID)) {
                        Text("Don't enforce").tag("")
                        Divider()
                        ForEach(inputManager.availableSources, id: \.id) { source in
                            Text(source.name).tag(source.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 180)
                }
            }
            .listStyle(.bordered)

            HStack(spacing: 4) {
                Button(action: addApps) {
                    Image(systemName: "plus")
                }
                Button(action: removeSelected) {
                    Image(systemName: "minus")
                }
                .disabled(selection.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 440, minHeight: 300)
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
}

struct AppIconView: NSViewRepresentable {
    let bundleID: String

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
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
