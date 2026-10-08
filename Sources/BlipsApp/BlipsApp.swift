import BlipsCore
import SwiftUI

@main
struct BlipsApp: App {
  @State private var model = AppModel()

  init() {
    AppUpdater.shared.start(repository: "flaviocopes/chip-pops")
    if AgentSkill.state == .outdated {
      _ = AgentSkill.install()
    }
  }

  var body: some Scene {
    Window("Chip Pops", id: "main") {
      ContentView()
        .environment(model)
        .frame(minWidth: 900, minHeight: 560)
    }
    .defaultSize(width: 1280, height: 800)
    .commands {
      BlipsCommands(model: model)
    }
  }
}

struct BlipsCommands: Commands {
  let model: AppModel

  var body: some Commands {
    CommandGroup(after: .appInfo) {
      Button("Check for Updates…") {
        AppUpdater.shared.checkForUpdates()
      }
      Divider()
      Button("Install Command Line Tool…") {
        CommandLineTool.install()
      }
      Button("Install Agent Skill…") {
        AgentSkill.installFromMenu()
      }
    }
    CommandGroup(replacing: .newItem) {}
    CommandMenu("Sound") {
      Button(model.playingID == nil ? "Play" : "Stop") { model.playOrStop() }
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(model.library == nil)
      Button("Next Sound") { model.move(by: 1) }
        .keyboardShortcut(.rightArrow, modifiers: .command)
        .disabled(model.library == nil)
      Button("Previous Sound") { model.move(by: -1) }
        .keyboardShortcut(.leftArrow, modifiers: .command)
        .disabled(model.library == nil)
      Divider()
      if let sound = model.selectedSound {
        Button("Export…") { model.export(sound) }
          .keyboardShortcut("e")
        Button("Copy File") { model.copyFile(sound) }
          .keyboardShortcut("c", modifiers: [.command, .shift])
        Button("Show in Finder") { model.revealInFinder(sound) }
          .keyboardShortcut("r", modifiers: [.command, .shift])
        Button("Open in sfxr.me") { model.openInSfxr(sound) }
          .disabled(sound.sfxrURL == nil)
      } else {
        Button("Export…") {}.disabled(true)
        Button("Copy File") {}.disabled(true)
        Button("Show in Finder") {}.disabled(true)
        Button("Open in sfxr.me") {}.disabled(true)
      }
    }
    CommandMenu("Library") {
      Button("Reload") { model.load() }
        .keyboardShortcut("r")
      Button("Generate…") { model.showsGenerateSheet = true }
        .disabled(model.generation != nil)
      Divider()
      Button("Show Library in Finder") { model.revealLibrary() }
        .disabled(model.library == nil)
    }
  }
}
