import BlipsCore
import Foundation

@main
enum BlipsCommand {
  static func main() {
    var arguments = Array(CommandLine.arguments.dropFirst())
    guard let name = arguments.first else {
      printHelp()
      return
    }
    arguments.removeFirst()

    switch name {
    case "help", "--help", "-h":
      if let command = arguments.first {
        guard let spec = Commands.all.first(where: { $0.name == command }) else {
          fail("There's no '\(command)' command. Run 'blips help' to see them.")
        }
        printHelp(spec)
      } else {
        printHelp()
      }
    case "version", "--version":
      print("blips \(Blips.version)")
    case "capabilities":
      do {
        try Commands.manifest.print(json: arguments.contains("--json"))
      } catch {
        fail(error.localizedDescription)
      }
    default:
      guard let spec = Commands.all.first(where: { $0.name == name }) else {
        fail("There's no '\(name)' command. Run 'blips help' to see them.")
      }
      if arguments.contains("--help") {
        printHelp(spec)
        return
      }
      do {
        try spec.run(Arguments.parse(arguments, for: spec))
      } catch {
        fail(error.localizedDescription)
      }
    }
  }

  static func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("blips: \(message)\n".utf8))
    exit(1)
  }

  static func printHelp() {
    print("blips \(Blips.version): 8-bit sound effects made with jsfxr, in categories, for the interfaces of your apps.")
    print()
    print("Usage: blips <command> [options]")
    print()
    let width = max(Commands.all.map(\.name.count).max() ?? 0, "capabilities".count)
    for spec in Commands.all {
      print("  \(spec.name.padding(toLength: width, withPad: " ", startingAt: 0))  \(spec.summary)")
    }
    print("  \("capabilities".padding(toLength: width, withPad: " ", startingAt: 0))  What blips can do, and what changed in each version")
    print()
    print("""
      A sound is named by its ID, like success-003, and IDs don't change when the library grows.
      play and export also take a category, like success, for all of its sounds.
      Add --json to any command for JSON output. Run 'blips help <command>' for its options.
      The library is in \(LibraryStore.defaultFolder.path), or in BLIPS_HOME when it's set.
      """)
  }

  static func printHelp(_ spec: Spec) {
    print(spec.summary + ".")
    print()
    print("Usage: blips \(spec.usage)")
    if let details = spec.details {
      print()
      print(details)
    }
  }
}

struct CLIError: LocalizedError {
  var message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}

/// A command: its name, how to call it, and the options that take a value.
struct Spec: Sendable {
  var name: String
  var usage: String
  var summary: String
  var options: [String] = []
  var details: String? = nil
  var run: @Sendable (Arguments) throws -> Void
}

struct Arguments: Sendable {
  var positionals: [String] = []
  var values: [String: String] = [:]
  var json = false

  func value(_ name: String) -> String? { values[name] }

  func number(_ name: String) throws -> Int? {
    guard let text = values[name] else { return nil }
    guard let number = Int(text), number > 0 else { throw CLIError("\(name) takes a positive number, not “\(text)”.") }
    return number
  }

  static func parse(_ arguments: [String], for spec: Spec) throws -> Arguments {
    var parsed = Arguments()
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      index += 1
      guard argument.hasPrefix("--"), argument.count > 2 else {
        parsed.positionals.append(argument)
        continue
      }
      var name = argument
      var value: String?
      if let equals = argument.firstIndex(of: "=") {
        name = String(argument[..<equals])
        value = String(argument[argument.index(after: equals)...])
      }
      if name == "--json" {
        parsed.json = true
        continue
      }
      guard spec.options.contains(name) else {
        throw CLIError("'\(spec.name)' has no \(name) option. Usage: blips \(spec.usage)")
      }
      if value == nil {
        guard index < arguments.count else { throw CLIError("\(name) needs a value.") }
        value = arguments[index]
        index += 1
      }
      parsed.values[name] = value
    }
    return parsed
  }
}
