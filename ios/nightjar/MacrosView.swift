import SwiftUI

// MARK: - The Macros tab
//
// The library, the block editor, the palette, and
// the run card. A macro is a playlist: blocks in
// order, each folding open to be configured where
// it sits. Everything the tab does goes through
// MacroStore and MacroRunner — the same store and
// runner Skelli's hands use.

struct MacrosView: View {
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var post: ListeningPost
    @EnvironmentObject private var emcon: Emcon
    @EnvironmentObject private var toasts: ToastCenter
    @ObservedObject private var runner = MacroRunner.shared

    @State private var macros: [Macro] = MacroStore.load()
    @State private var shareItem: ShareItem?
    @State private var showImporter = false
    @State private var macroToDelete: Macro?
    @State private var editingMacro: Macro?

    var body: some View {
        NavigationStack {
            List {
                if runner.running {
                    Section("Now running") {
                        HStack {
                            ProgressView()
                            VStack(alignment: .leading,
                                   spacing: 2) {
                                Text(runner.currentMacroName)
                                    .font(.callout.weight(.semibold))
                                Text(runner.currentStep)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Stop", role: .destructive) {
                                Haptics.tap()
                                runner.stop()
                            }
                            .font(.callout)
                        }
                        ForEach(runner.log.suffix(6)) { line in
                            Text("\(line.mark) \(line.text)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Library") {
                    if macros.isEmpty {
                        Text("No macros yet. Build one block "
                            + "by block below, start from a "
                            + "template, or tell Skelli the "
                            + "steps — she builds them too.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(macros) { macro in
                        Button {
                            Haptics.tap()
                            editingMacro = macro
                        } label: {
                            HStack {
                                MacroRow(
                                    macro: macro,
                                    running: runner.running
                                        && runner.currentMacroName
                                            == macro.name)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete",
                                   role: .destructive) {
                                macroToDelete = macro
                            }
                            Button("Duplicate") {
                                Haptics.tap()
                                var copy = macro
                                copy.id = UUID()
                                copy.name = macro.name + " copy"
                                copy.blocks = macro.blocks.map {
                                    block in
                                    var blockCopy = block
                                    blockCopy.id = UUID()
                                    return blockCopy
                                }
                                macros.append(copy)
                                persist()
                            }
                        }
                    }
                }
                Section("Start from a template") {
                    ForEach(MacroTemplates.all,
                            id: \.title) { template in
                        Button {
                            Haptics.tap()
                            let macro = template.make()
                            macros.append(macro)
                            persist()
                            editingMacro = macro
                        } label: {
                            Label("New — \(template.title)",
                                  systemImage: "square.stack.3d.up")
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section("The library file") {
                    Button {
                        Haptics.tap()
                        if let url = MacroStore.exportURL(macros) {
                            shareItem = ShareItem(items: [url])
                        }
                    } label: {
                        Label("Export the library (.json)",
                              systemImage: "square.and.arrow.up")
                    }
                    .foregroundStyle(.primary)
                    Button {
                        Haptics.tap()
                        showImporter = true
                    } label: {
                        Label("Import macros (.json)",
                              systemImage: "square.and.arrow.down")
                    }
                    .foregroundStyle(.primary)
                    Text("Imports arrive as copies — an "
                        + "import never overwrites a macro "
                        + "already here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Macros")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        var name = "New Macro"
                        var n = 2
                        while macros.contains(
                            where: { $0.name == name }) {
                            name = "New Macro \(n)"
                            n += 1
                        }
                        let macro = Macro(name: name)
                        macros.append(macro)
                        persist()
                        editingMacro = macro
                    } label: {
                        Label("New macro", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: item.items)
            }
            .sheet(item: $editingMacro) { macro in
                NavigationStack {
                    MacroEditorView(
                        macro: macro,
                        onSave: { save($0) },
                        onDelete: {
                            macros.removeAll {
                                $0.id == macro.id
                            }
                            persist()
                        })
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.json]) { result in
                importMacros(result)
            }
            .confirmationDialog(
                "Delete this macro?",
                isPresented: Binding(
                    get: { macroToDelete != nil },
                    set: { if !$0 { macroToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete "
                       + (macroToDelete?.name ?? "macro"),
                       role: .destructive) {
                    if let macro = macroToDelete {
                        macros.removeAll { $0.id == macro.id }
                        persist()
                    }
                    macroToDelete = nil
                    Haptics.success()
                }
                Button("Cancel", role: .cancel) {
                    macroToDelete = nil
                }
            } message: {
                Text("The playlist goes. Its blocks were "
                    + "never the engines — those stay.")
            }
            .onAppear {
                macros = MacroStore.load()
            }
        }
    }

    private func save(_ macro: Macro) {
        if let index = macros.firstIndex(
            where: { $0.id == macro.id }) {
            macros[index] = macro
            persist()
        }
    }

    private func persist() {
        MacroStore.save(macros)
    }

    private func importMacros(
        _ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        guard url.startAccessingSecurityScopedResource()
        else {
            toasts.show("That file would not open.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url),
              let imported = MacroStore.decodeImport(data)
        else {
            toasts.show("That is not a nightjar macro file.")
            return
        }
        macros.append(contentsOf: imported)
        persist()
        toasts.show(imported.count == 1
            ? "One macro imported."
            : "\(imported.count) macros imported.")
    }
}

private struct MacroRow: View {
    let macro: Macro
    let running: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: macro.icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color(hex: macro.colorHex),
                            in: RoundedRectangle(
                                cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(macro.name)
                    .font(.callout.weight(.semibold))
                Text("\(macro.blocks.count) block"
                    + (macro.blocks.count == 1 ? "" : "s")
                    + (macro.note.isEmpty
                       ? "" : " — \(macro.note)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if running {
                Spacer()
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }
}

// MARK: - The block editor

struct MacroEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var post: ListeningPost
    @EnvironmentObject private var emcon: Emcon
    @ObservedObject private var runner = MacroRunner.shared
    @StateObject private var book = PayloadBook()

    @State private var draft: Macro
    @State private var expanded: Set<UUID> = []
    @State private var showPalette = false
    @State private var showRunCard = false
    @State private var confirmDelete = false

    let onSave: (Macro) -> Void
    let onDelete: () -> Void

    init(macro: Macro,
         onSave: @escaping (Macro) -> Void,
         onDelete: @escaping () -> Void) {
        _draft = State(initialValue: macro)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var problems: [String] {
        MacroValidator.problems(in: draft, book: book)
    }

    var body: some View {
        List {
            Section("Dress it") {
                HStack(spacing: 12) {
                    Image(systemName: draft.icon)
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Color(hex: draft.colorHex),
                                    in: RoundedRectangle(
                                        cornerRadius: 12))
                    TextField("Name — Night Watch, …",
                              text: $draft.name)
                        .font(.headline)
                        .onChange(of: draft.name) {
                            _ in commit()
                        }
                }
                TextField("Note — what this playlist is for",
                          text: $draft.note)
                    .font(.callout)
                    .onChange(of: draft.note) { _ in commit() }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Icon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(
                        repeating: GridItem(.flexible(),
                                            spacing: 4),
                        count: 8), spacing: 8) {
                        ForEach(MacroPalette.icons, id: \.self) {
                            icon in
                            Image(systemName: icon)
                                .font(.body)
                                .frame(width: 36, height: 36)
                                .background(
                                    draft.icon == icon
                                    ? Color(hex: draft.colorHex)
                                        .opacity(0.25)
                                    : Color.clear,
                                    in: RoundedRectangle(
                                        cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(
                                        cornerRadius: 8)
                                        .stroke(
                                            draft.icon == icon
                                            ? Color(hex:
                                                draft.colorHex)
                                            : Color.clear,
                                            lineWidth: 2))
                                .onTapGesture {
                                    Haptics.tap()
                                    draft.icon = icon
                                    commit()
                                }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Colour")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(
                        repeating: GridItem(.flexible(),
                                            spacing: 8),
                        count: 5), spacing: 10) {
                        ForEach(MacroPalette.colors,
                                id: \.hex) { color in
                            Circle()
                                .fill(Color(hex: color.hex))
                                .frame(width: 34, height: 34)
                                .overlay(
                                    Circle().stroke(
                                        draft.colorHex == color.hex
                                        ? Color.white : Color.clear,
                                        lineWidth: 3))
                                .onTapGesture {
                                    Haptics.tap()
                                    draft.colorHex = color.hex
                                    commit()
                                }
                        }
                    }
                }
            }
            Section {
                if draft.blocks.isEmpty {
                    Text("Empty. Add a block — the whole "
                        + "instrument is in the palette.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(draft.blocks) { block in
                    MacroBlockCard(
                        block: block, book: book,
                        expanded: expanded.contains(block.id),
                        onToggle: {
                            Haptics.select()
                            if expanded.contains(block.id) {
                                expanded.remove(block.id)
                            } else {
                                expanded.insert(block.id)
                            }
                        },
                        onChange: { update(block: $0) },
                        onDuplicate: { duplicate(block) },
                        onRemove: { remove(block) })
                }
                .onMove { from, to in
                    draft.blocks.move(fromOffsets: from,
                                      toOffset: to)
                    commit()
                }
                .onDelete { offsets in
                    draft.blocks.remove(atOffsets: offsets)
                    commit()
                }
                Button {
                    Haptics.tap()
                    showPalette = true
                } label: {
                    Label("Add a block",
                          systemImage: "plus.circle.fill")
                }
                .foregroundStyle(.primary)
            } header: {
                Text("The playlist — \(draft.blocks.count) block"
                    + (draft.blocks.count == 1 ? "" : "s"))
            } footer: {
                Text("Drag to reorder. Tap a block to fold "
                    + "its settings open.")
                    .font(.caption)
            }
            Section("Run") {
                if runner.running
                    && runner.currentMacroName == draft.name {
                    HStack {
                        ProgressView()
                        Text(runner.currentStep)
                            .font(.caption)
                    }
                    ForEach(runner.log.suffix(8)) { line in
                        Text("\(line.mark) \(line.text)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Button("Stop the run",
                           role: .destructive) {
                        Haptics.tap()
                        runner.stop()
                    }
                } else {
                    if !problems.isEmpty {
                        ForEach(problems, id: \.self) { p in
                            Text("⚠ \(p)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Button {
                        Haptics.tap()
                        showRunCard = true
                    } label: {
                        Label("Run it",
                              systemImage: "play.fill")
                    }
                    .disabled(!problems.isEmpty
                        || runner.running)
                    .foregroundStyle(.primary)
                    if runner.running {
                        Text("Another macro is running — "
                            + "stop it first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !runner.running
                        && !runner.lastSummary.isEmpty {
                        Text("Last run: \(runner.lastSummary)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button("Delete this macro",
                       role: .destructive) {
                    confirmDelete = true
                }
            }
        }
        .navigationTitle(draft.name.isEmpty
            ? "Macro" : draft.name)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    Haptics.tap()
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showPalette) {
            MacroPaletteSheet { kind in
                var block = MacroBlock(kind: kind)
                block.config = MacroCatalog.defaults(
                    for: kind)
                draft.blocks.append(block)
                expanded.insert(block.id)
                commit()
            }
        }
        .sheet(isPresented: $showRunCard) {
            MacroRunCardSheet(macro: draft, book: book,
                              onRun: {
                runner.run(draft, mouth: mouth,
                           post: post, emcon: emcon,
                           book: book)
            })
        }
        .confirmationDialog(
            "Delete this macro?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete “\(draft.name)”",
                   role: .destructive) {
                Haptics.success()
                onDelete()
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The playlist goes. Its blocks were "
                + "never the engines — those stay.")
        }
    }

    private func commit() {
        draft.modifiedAt = Date()
        onSave(draft)
    }

    private func update(block: MacroBlock) {
        if let index = draft.blocks.firstIndex(
            where: { $0.id == block.id }) {
            draft.blocks[index] = block
            commit()
        }
    }

    private func duplicate(_ block: MacroBlock) {
        Haptics.tap()
        var copy = block
        copy.id = UUID()
        if let index = draft.blocks.firstIndex(
            where: { $0.id == block.id }) {
            draft.blocks.insert(copy, at: index + 1)
            expanded.insert(copy.id)
            commit()
        }
    }

    private func remove(_ block: MacroBlock) {
        Haptics.tap()
        draft.blocks.removeAll { $0.id == block.id }
        expanded.remove(block.id)
        commit()
    }
}

// MARK: - One block, folded or open

struct MacroBlockCard: View {
    let block: MacroBlock
    @ObservedObject var book: PayloadBook
    let expanded: Bool
    let onToggle: () -> Void
    let onChange: (MacroBlock) -> Void
    let onDuplicate: () -> Void
    let onRemove: () -> Void

    private var spec: MacroKindSpec {
        MacroCatalog.spec(block.kind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                onToggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: spec.icon)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(spec.title)
                            .font(.callout.weight(.semibold))
                        Text(MacroSummary.line(for: block))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if block.repeatCount > 1 {
                        Text("×\(block.repeatCount)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: expanded
                          ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
            .buttonStyle(.plain)
            if expanded {
                Divider()
                ForEach(spec.fields.filter(isVisible),
                        id: \.key) { field in
                    fieldRow(field)
                }
                Stepper(value: repeatBinding, in: 1...10) {
                    Text("Repeat ×\(block.repeatCount)")
                        .font(.callout)
                }
                HStack {
                    Button("Duplicate block") {
                        onDuplicate()
                    }
                    .font(.caption)
                    Spacer()
                    Button("Remove block",
                           role: .destructive) {
                        onRemove()
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func isVisible(_ field: MacroField) -> Bool {
        if block.kind == "serveStart"
            && ["tcp", "tcpPort", "udp", "udpPort",
                "http", "httpPort"].contains(field.key) {
            return block.value("mode") == "Custom doors"
        }
        if block.kind == "persona" && field.key == "name" {
            return block.value("mode") != "Drop"
        }
        return true
    }

    private var repeatBinding: Binding<Int> {
        Binding(get: { block.repeatCount },
                set: { value in
                    var copy = block
                    copy.repeatCount = value
                    onChange(copy)
                })
    }

    private func textBinding(_ key: String) -> Binding<String> {
        Binding(get: { block.config[key] ?? "" },
                set: { value in
                    var copy = block
                    copy.config[key] = value
                    onChange(copy)
                })
    }

    private func flagBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { block.config[key] == "on" },
                set: { value in
                    var copy = block
                    copy.config[key] = value ? "on" : "off"
                    onChange(copy)
                })
    }

    @ViewBuilder
    private func fieldRow(_ field: MacroField) -> some View {
        switch field.control {
        case .text:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(field.label)
                        .font(.callout)
                    Spacer()
                    TextField(field.placeholder,
                              text: textBinding(field.key))
                        .multilineTextAlignment(.trailing)
                        .font(.callout)
                        .frame(maxWidth: 210)
                }
                if block.kind == "costume"
                    && field.key == "name" {
                    ScrollView(.horizontal,
                               showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(MacroNames.costumeNames(),
                                    id: \.self) { name in
                                Text(name)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.thinMaterial,
                                                in: Capsule())
                                    .onTapGesture {
                                        Haptics.tap()
                                        var copy = block
                                        copy.config["name"] = name
                                        onChange(copy)
                                    }
                            }
                        }
                    }
                }
            }
        case .number:
            HStack {
                Text(field.label)
                    .font(.callout)
                Spacer()
                TextField(field.placeholder,
                          text: textBinding(field.key))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.callout.monospaced())
                    .frame(maxWidth: 120)
            }
        case .toggle:
            Toggle(field.label,
                   isOn: flagBinding(field.key))
                .font(.callout)
        case .picker(let options):
            Picker(field.label,
                   selection: textBinding(field.key)) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .font(.callout)
        case .payloadPicker:
            Picker(field.label,
                   selection: textBinding(field.key)) {
                Text("None").tag("")
                ForEach(book.items, id: \.name) { payload in
                    Text(payload.name).tag(payload.name)
                }
            }
            .pickerStyle(.menu)
            .font(.callout)
        case .chestPicker:
            Picker(field.label,
                   selection: textBinding(field.key)) {
                Text("None").tag("")
                ForEach(MacroNames.chestNames(),
                        id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)
            .font(.callout)
        case .personaPicker:
            Picker(field.label,
                   selection: textBinding(field.key)) {
                Text("None").tag("")
                ForEach(MacroNames.personaNames(),
                        id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)
            .font(.callout)
        case .remotePicker:
            Picker(field.label,
                   selection: textBinding(field.key)) {
                Text("None").tag("")
                ForEach(MacroNames.remoteNames(),
                        id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)
            .font(.callout)
        case .helmButtonPicker:
            Picker(field.label,
                   selection: textBinding(field.key)) {
                Text("None").tag("")
                ForEach(MacroNames.helmButtons(
                    remote: block.value("remote")),
                        id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)
            .font(.callout)
        }
    }
}

// MARK: - The palette

struct MacroPaletteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(MacroCatalog.categories,
                        id: \.self) { category in
                    Section(category) {
                        ForEach(MacroCatalog.specs.filter {
                            $0.category == category
                        }, id: \.kind) { spec in
                            Button {
                                Haptics.tap()
                                onPick(spec.kind)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: spec.icon)
                                        .frame(width: 26)
                                    VStack(alignment: .leading,
                                           spacing: 1) {
                                        Text(spec.title)
                                            .font(.callout
                                                .weight(.semibold))
                                        Text(spec.blurb)
                                            .font(.caption)
                                            .foregroundStyle(
                                                .secondary)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Add a block")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - The run card

struct MacroRunCardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let macro: Macro
    @ObservedObject var book: PayloadBook
    let onRun: () -> Void

    private var problems: [String] {
        MacroValidator.problems(in: macro, book: book)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MacroRow(macro: macro, running: false)
                    if !macro.note.isEmpty {
                        Text(macro.note)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("The playlist") {
                    ForEach(Array(macro.blocks.enumerated()),
                            id: \.element.id) { index, block in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            Image(systemName:
                                MacroCatalog.spec(block.kind).icon)
                                .frame(width: 22)
                            VStack(alignment: .leading,
                                   spacing: 1) {
                                Text(MacroCatalog.spec(
                                    block.kind).title)
                                    .font(.callout)
                                Text(MacroSummary.line(
                                    for: block))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if block.repeatCount > 1 {
                                Spacer()
                                Text("×\(block.repeatCount)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !problems.isEmpty {
                    Section("Not ready") {
                        ForEach(problems, id: \.self) { p in
                            Text("⚠ \(p)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Section {
                    Text("A run does exactly what these "
                        + "blocks say, in order. Waits hold "
                        + "the list; a block that cannot run "
                        + "stops the run and says why — in "
                        + "the run log and the night log.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Run this macro?")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Not yet") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Run it") {
                        Haptics.tap()
                        onRun()
                        dismiss()
                    }
                    .disabled(!problems.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
