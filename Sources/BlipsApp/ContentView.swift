import BlipsCore
import SwiftUI

/// The categories in a sidebar, the sounds as a grid of waveforms, and the selected sound in the inspector.
struct ContentView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    NavigationSplitView {
      Sidebar()
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
    } detail: {
      Group {
        if model.library == nil {
          EmptyState(
            symbol: "waveform",
            title: "No sounds yet",
            message: """
              Blips makes its sounds with jsfxr, in \(LibraryGenerator.categories.count) categories, combos and \
              jingles included, and keeps only the ones that are clearly different from the others.
              """
          ) {
            GenerateButton()
          }
        } else if model.sounds.isEmpty {
          EmptyState(symbol: "magnifyingglass", title: "No sounds match", message: "Try other words, or look in All Sounds.") {
            EmptyView()
          }
        } else {
          SoundGrid()
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Surface.canvas)
      .navigationTitle(model.title)
      .navigationSubtitle(model.library == nil ? "" : "\(model.sounds.count) sounds")
      .inspector(isPresented: $model.showsInspector) {
        SoundInspector()
          .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
      }
      .toolbar {
        ToolbarItem {
          Button {
            model.showsInspector.toggle()
          } label: {
            Label("Inspector", systemImage: "sidebar.trailing")
          }
          .help(model.showsInspector ? "Hide the inspector" : "Show the inspector")
        }
      }
    }
    .searchable(text: $model.search, placement: .sidebar, prompt: "Search sounds")
    .sheet(isPresented: $model.showsGenerateSheet) {
      GenerateSheet()
    }
    .alert(
      "Blips",
      isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    ) {
      Button("OK") {}
    } message: {
      Text(model.errorMessage ?? "")
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      model.load()
    }
  }
}

struct Sidebar: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    List(selection: $model.sidebar) {
      if let library = model.library {
        Label {
          Text("All Sounds")
        } icon: {
          CategoryIcon(category: "all", size: 20)
        }
        .badge(library.sounds.count)
        .tag(SidebarItem.all)

        ForEach(SoundCategory.Group.allCases, id: \.self) { group in
          let categories = library.categories.filter { $0.group == group }
          if !categories.isEmpty {
            Section(group.title) {
              ForEach(categories) { category in
                CategoryRow(category: category, count: model.counts[category.id] ?? 0)
              }
            }
          }
        }
      }
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .bottom) {
      LibraryFooter()
    }
  }
}

struct CategoryRow: View {
  @Environment(AppModel.self) private var model
  let category: SoundCategory
  let count: Int

  var body: some View {
    Label {
      Text(category.name)
    } icon: {
      CategoryIcon(category: category.id, size: 20)
    }
    .badge(count)
    .tag(SidebarItem.category(category.id))
    .help(category.summary)
    .contextMenu {
      Button("Export \(category.name) Sounds…") {
        model.export(model.library?.sounds(category: category.id) ?? [], name: category.name.lowercased())
      }
    }
  }
}

struct LibraryFooter: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 1) {
        Text(model.library.map { "\($0.sounds.count) sounds" } ?? "No library")
          .font(Typography.bodyStrong)
        Text(model.library.map { "Seed \($0.seed) · jsfxr \($0.jsfxr)" } ?? "Generate it to start")
          .font(Typography.caption)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
          .help("Every sound comes from this seed. The same ID is another sound in a library from another seed.")
      }
      Spacer(minLength: 0)
      Button {
        model.showsGenerateSheet = true
      } label: {
        Image(systemName: "wand.and.stars")
      }
      .buttonStyle(.borderless)
      .help("Generate the library")
      .accessibilityLabel("Generate the library")
      Button {
        model.revealLibrary()
      } label: {
        Image(systemName: "folder")
      }
      .buttonStyle(.borderless)
      .disabled(model.library == nil)
      .help("Show the library in the Finder")
      .accessibilityLabel("Show the library in the Finder")
    }
    .padding(12)
  }
}

struct GenerateButton: View {
  @Environment(AppModel.self) private var model
  var seed: UInt32? = LibraryGenerator.defaultSeed

  var body: some View {
    if let generation = model.generation {
      ProgressView(value: Double(generation.categoriesDone), total: Double(generation.categories)) {
        Text("Generating: \(generation.sounds.formatted()) sounds, \(generation.categoriesDone) of \(generation.categories) categories done")
          .font(Typography.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      .frame(width: 300)
    } else {
      Button("Generate the Library") {
        if let seed {
          model.generate(seed: seed)
        }
      }
      .buttonStyle(GradientButtonStyle())
      .disabled(seed == nil)
    }
  }
}

/// Generates the main library again, a new one from a random seed, or one from a seed you type.
struct GenerateSheet: View {
  enum Choice: Hashable {
    case main, new, typed
  }

  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var choice = Choice.main
  @State private var randomSeed = LibraryGenerator.randomSeed()
  @State private var typed = ""

  private var seed: UInt32? {
    switch choice {
    case .main: LibraryGenerator.defaultSeed
    case .new: randomSeed
    case .typed: UInt32(typed.filter { $0 != "," && $0 != "." && !$0.isWhitespace })
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Generate the library")
        .font(Typography.title)
      Text("""
        Blips rolls each category's sounds with jsfxr and keeps a roll only when it's clearly different \
        from every sound already in the category. The seed decides every roll, so the same seed always \
        gives the same sounds, and another seed a whole different library.
        """)
        .font(Typography.body)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      Picker("Library", selection: $choice) {
        Text("Main Library").tag(Choice.main)
        Text("New Sounds").tag(Choice.new)
        Text("Seed…").tag(Choice.typed)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .disabled(model.generation != nil)

      Group {
        switch choice {
        case .main:
          Text("Seed 1, the library that sound IDs and packs refer to.")
        case .new:
          HStack(spacing: 8) {
            Text("Seed \(String(randomSeed)). Note it down to get back to these sounds.")
              .textSelection(.enabled)
            Button("Roll Again") { randomSeed = LibraryGenerator.randomSeed() }
              .controlSize(.small)
          }
        case .typed:
          HStack(spacing: 8) {
            TextField("Seed", text: $typed)
              .textFieldStyle(.roundedBorder)
              .frame(width: 120)
            Text(seed == nil && !typed.isEmpty ? "A seed is a whole number." : "The seed of a library you made before.")
          }
        }
      }
      .font(Typography.caption)
      .foregroundStyle(.secondary)
      .frame(minHeight: 22, alignment: .leading)

      HStack {
        if let current = model.library?.seed {
          Text("Your library is from seed \(String(current)).")
            .font(Typography.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
          .disabled(model.generation != nil)
        GenerateButton(seed: seed)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 480)
  }
}
