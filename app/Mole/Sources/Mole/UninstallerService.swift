import AppKit
import Foundation

struct AppItem: Identifiable, Equatable {
  let id = UUID()
  let name: String
  let url: URL
  let icon: NSImage?
  let size: String
}

class UninstallerService: ObservableObject {
  @Published var apps: [AppItem] = []
  @Published var isUninstalling = false
  @Published var currentLog = ""

  init() {
    // Prefetch on launch
    Task {
      await scanApps()
    }
  }

  func scanApps() async {
    // If we already have data, don't block.
    if !apps.isEmpty { return }

    let fileManager = FileManager.default
    let appsDir = URL(fileURLWithPath: "/Applications")

    do {
      let fileURLs = try fileManager.contentsOfDirectory(
        at: appsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)

      // A. Populate Basic Info Immediately
      var initialApps: [AppItem] = []
      for url in fileURLs where url.pathExtension == "app" {
        let name = url.deletingPathExtension().lastPathComponent
        initialApps.append(AppItem(name: name, url: url, icon: nil, size: ""))
      }
      initialApps.sort { $0.name < $1.name }

      await MainActor.run {
        self.apps = initialApps
      }

      // B. Slow Path: Calculate Sizes and Fetch Icons in Background
      await withTaskGroup(of: (UUID, NSImage?, String).self) { group in
        for app in initialApps {
          group.addTask { [app] in
            // Fetch Icon
            let icon = NSWorkspace.shared.icon(forFile: app.url.path)
            // Calculate Size
            let size = self.calculateSize(for: app.url)
            return (app.id, icon, size)
          }
        }

        for await (id, icon, sizeStr) in group {
          await MainActor.run {
            if let index = self.apps.firstIndex(where: { $0.id == id }) {
              let old = self.apps[index]
              self.apps[index] = AppItem(name: old.name, url: old.url, icon: icon, size: sizeStr)
            }
          }
        }
      }

    } catch {
      print("Error scanning apps: \(error)")
    }
  }

  func uninstall(_ app: AppItem) async {
    await MainActor.run {
      self.isUninstalling = true
      self.currentLog = "Preparing to remove \(app.name)..."
    }

    let containerPath =
      FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
      .appendingPathComponent("Containers").appendingPathComponent("com.example.\(app.name)")
      .path ?? "~/Library/Containers/..."

    let steps = [
      "Analyzing Bundle Structure...",
      "Identifying App Sandbox...",
      "Locating Application Support Files...",
      "Finding Preferences Plist...",
      "Scanning for Caches...",
      "Removing \(app.name).app...",
      "Cleaning Container: \(containerPath)...",
      "Unlinking LaunchAgents...",
      "Final Cleanup...",
    ]

    for step in steps {
      await MainActor.run { self.currentLog = step }
      // Random "Work" Delay
      let delay = UInt64.random(in: 300_000_000...800_000_000)
      try? await Task.sleep(nanoseconds: delay)
    }

    await MainActor.run {
      self.isUninstalling = false
      self.currentLog = "Uninstalled \(app.name)"
      // Simulate removal from list
      if let idx = self.apps.firstIndex(of: app) {
        self.apps.remove(at: idx)
      }
    }
  }

  private func calculateSize(for url: URL) -> String {
    guard
      let enumerator = FileManager.default.enumerator(
        at: url, includingPropertiesForKeys: [.fileSizeKey])
    else { return "Unknown" }
    var totalSize: Int64 = 0
    for case let fileURL as URL in enumerator {
      do {
        let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = resourceValues.fileSize {
          totalSize += Int64(fileSize)
        }
      } catch {}
    }
    return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
  }
}
