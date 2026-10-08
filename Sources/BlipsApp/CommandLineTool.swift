import AppKit

/// Links the `blips` command inside the app into ~/.local/bin, which needs no password.
@MainActor
enum CommandLineTool {
  static var bundled: URL {
    Bundle.main.bundleURL.appending(path: "Contents/Helpers/blips")
  }

  static var link: URL {
    FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin/blips")
  }

  static func install() {
    let alert = NSAlert()
    do {
      guard FileManager.default.isExecutableFile(atPath: bundled.path) else {
        throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "This copy of Chip Pops has no blips command inside. Build it with Scripts/build-app.sh."])
      }
      try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
      if (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil || FileManager.default.fileExists(atPath: link.path) {
        try FileManager.default.removeItem(at: link)
      }
      try FileManager.default.createSymbolicLink(at: link, withDestinationURL: bundled)
      alert.messageText = "The blips command is installed"
      alert.informativeText = "It's linked at ~/.local/bin/blips. Run `blips help` to see what it does."
    } catch {
      alert.alertStyle = .warning
      alert.messageText = "The blips command wasn't installed"
      alert.informativeText = error.localizedDescription
    }
    alert.runModal()
  }
}
