import AppKit

/// Installs the agent skill bundled in the app, which teaches coding agents to pick sounds for an
/// app with the `blips` command. It goes in ~/.agents/skills/blips, and the skill folders of
/// Claude Code, Cursor and Codex link to it.
enum AgentSkill {
  enum State {
    case installed, outdated, missing
  }

  static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
  static var folder: URL { home.appending(path: ".agents/skills/blips") }
  static var bundled: URL? { Bundle.main.url(forResource: "SKILL", withExtension: "md") }
  /// Agents that read skills from a folder of their own, linked to the shared one when they're installed.
  static let agents = [".claude", ".cursor", ".codex"]

  static var state: State {
    guard let bundled, let fresh = try? Data(contentsOf: bundled),
      let current = try? Data(contentsOf: folder.appending(path: "SKILL.md"))
    else { return .missing }
    return current == fresh ? .installed : .outdated
  }

  /// Copies the skill in and links it for each agent that's installed. Returns what went wrong, if anything.
  static func install() -> String? {
    let fm = FileManager.default
    guard let bundled else { return "The skill is missing from this copy of Chip Pops. Build it with Scripts/build-app.sh." }
    do {
      try fm.createDirectory(at: folder, withIntermediateDirectories: true)
      try replace(folder.appending(path: "SKILL.md"), with: bundled)
      for agent in agents {
        let agentHome = home.appending(path: agent)
        guard fm.fileExists(atPath: agentHome.path) else { continue }
        let skills = agentHome.appending(path: "skills")
        try fm.createDirectory(at: skills, withIntermediateDirectories: true)
        let link = skills.appending(path: "blips")
        // A link someone made, to this skill or another one, stays as it is.
        if (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil { continue }
        if fm.fileExists(atPath: link.path) {
          try replace(link.appending(path: "SKILL.md"), with: bundled)
        } else {
          try fm.createSymbolicLink(at: link, withDestinationURL: folder)
        }
      }
    } catch {
      return error.localizedDescription
    }
    return nil
  }

  private static func replace(_ file: URL, with source: URL) throws {
    try? FileManager.default.removeItem(at: file)
    try FileManager.default.copyItem(at: source, to: file)
  }

  @MainActor
  static func installFromMenu() {
    let alert = NSAlert()
    if let problem = install() {
      alert.alertStyle = .warning
      alert.messageText = "The agent skill wasn't installed"
      alert.informativeText = problem
    } else {
      alert.messageText = "The agent skill is installed"
      alert.informativeText = "Claude Code, Cursor and Codex now know how to add sounds to your apps with the blips command. Install the command too, from the same menu."
    }
    alert.runModal()
  }
}
