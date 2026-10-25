import SwiftUI

/// Everything about the island itself, in one place.
///
/// Four tabs rather than four sidebar rows: they are all the same object seen
/// from different angles, and the sidebar is already six rows long. The tab is
/// remembered, so coming back lands where you left.
struct IslandSettingsView: View {
    @ObservedObject var state: AppState
    @AppStorage("islandTab") private var tab: String = Tab.layout.rawValue

    enum Tab: String, CaseIterable, Identifiable {
        case layout, content, activity, behavior
        var id: String { rawValue }
        var title: String {
            switch self {
            case .layout:   return "Layout"
            case .content:  return "Content"
            case .activity: return "Activity"
            case .behavior: return "Behavior"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch Tab(rawValue: tab) ?? .layout {
            case .layout:   layoutTab
            case .content:  contentTab
            case .activity: activityTab
            case .behavior: behaviorTab
            }
        }
    }

    // MARK: – Layout

    @ViewBuilder private var layoutTab: some View {
        GroupBox("Buttons around the island") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Anything here sits on the island's border, so one click opens it "
                     + "without opening the island first.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                IslandRingEditor(state: state)
            }
            .padding(6)
        }

        GroupBox("Big screen") {
            VStack(alignment: .leading, spacing: 10) {
                Text("How large the island gets for views that are a screen rather than a "
                     + "card — an agenda, say. Views that are cards keep the size they "
                     + "were designed against.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                sizeRow("Width", $state.largeIslandWidth,
                        AppState.largeWidthRange, IslandConst.defaultLargeSize.width)
                sizeRow("Height", $state.largeIslandHeight,
                        AppState.largeHeightRange, IslandConst.defaultLargeSize.height)
            }
            .padding(6)
        }
    }

    /// Off takes the designed size; on reveals a slider. The shape the rest of
    /// Settings already uses for a measured-or-chosen number.
    @ViewBuilder
    private func sizeRow(_ title: String, _ value: Binding<CGFloat?>,
                         _ range: ClosedRange<CGFloat>, _ fallback: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle(title, isOn: Binding(
                    get: { value.wrappedValue != nil },
                    set: { value.wrappedValue = $0 ? fallback : nil }
                ))
                Spacer()
                Text(value.wrappedValue.map { "\(Int($0)) pt" } ?? "\(Int(fallback)) pt")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            if let v = value.wrappedValue {
                Slider(value: Binding(get: { v }, set: { value.wrappedValue = $0 }),
                       in: range, step: 10)
            }
        }
    }

    // MARK: – Content

    @ViewBuilder private var contentTab: some View {
        GroupBox("What the island carries") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Which pills are on. A pill does not have to be on to have a button — "
                     + "a button opens its app or its dashboard either way — but only the ones "
                     + "that are on report what they are doing.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Set these under Active pills.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(6)
        }

        #if !APPSTORE
        GroupBox("Now Playing") {
            VStack(alignment: .leading, spacing: 8) {
                Text("How far the player's two round buttons jump. They are set apart "
                     + "because they are usually wanted apart — a longer jump forward "
                     + "clears an ad, a shorter one back catches what you missed.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                skipRow("Back", $state.skipBackSeconds)
                skipRow("Forward", $state.skipForwardSeconds)
                Text("The number is drawn on the button. 5, 10, 15, 30, 45, 60, 75 and 90 "
                     + "get the system's own numbered dial; any other value is written onto "
                     + "a plain one.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(6)
        }
        #endif
    }

    @ViewBuilder
    private func skipRow(_ title: String, _ value: Binding<Int>) -> some View {
        Stepper(value: value, in: AppState.skipSecondsRange) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue) s")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: – Activity

    @ViewBuilder private var activityTab: some View {
        GroupBox("What it shows by itself") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Home, auto-close and how long it waits before it decides you have gone — "
                     + "these still live under General for now.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(6)
        }
    }

    // MARK: – Behavior

    @ViewBuilder private var behaviorTab: some View {
        GroupBox("Where it sits") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Island sits at", selection: $state.islandPosition) {
                    ForEach(IslandAnchor.presets, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                    // An island that was dragged somewhere is not one of the
                    // six, and a picker with no matching tag shows blank.
                    if IslandAnchor.isFree(state.islandPosition) {
                        Text("Where you dropped it").tag(state.islandPosition)
                    }
                }
                Text("Hold the resting island for two seconds and it comes unstuck: "
                     + "it follows the pointer, across displays, until you let go. "
                     + "Drop it near an edge and it settles into that corner.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(6)
        }

        GroupBox("Opening") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Which display the island lives on, how tall it rests and the shortcut "
                     + "that calls it still live under General for now.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(6)
        }
    }
}

/// Arranging the ring.
///
/// A list rather than a drag-and-drop miniature: it is keyboard-reachable, it
/// is the thing a drag would have to fall back to anyway, and it makes the
/// feature usable without a gesture to get wrong.
struct IslandRingEditor: View {
    @ObservedObject var state: AppState

    private var buttons: [IslandEdgeButton] { state.edgeButtons }

    private var unusedActions: [IslandEdgeAction] {
        let taken = Set(buttons.map(\.action))
        return IslandEdgeAction.allCases.filter { !taken.contains($0.rawValue) }
    }

    private var unused: [PillDefinition] {
        let taken = Set(buttons.map(\.action))
        return PillCatalog.available.filter { !taken.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if buttons.isEmpty {
                Text("No buttons yet.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            ForEach(buttons) { button in
                row(button)
            }

            if !unused.isEmpty || !unusedActions.isEmpty {
                Menu {
                    ForEach(unusedActions) { a in
                        Button(a.title) { add(a.rawValue) }
                    }
                    if !unused.isEmpty && !unusedActions.isEmpty { Divider() }
                    ForEach(unused, id: \.id) { def in
                        Button(def.name) { add(def.id) }
                    }
                } label: {
                    Label("Add a button", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.top, 2)
            }
        }
    }

    private func row(_ button: IslandEdgeButton) -> some View {
        let def = PillCatalog.definition(for: button.action)
        let act = IslandEdgeAction(rawValue: button.action)
        return HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: def?.color ?? act?.colorHex ?? "#8E939C"))
                .frame(width: 10, height: 10)
            if let logo = def?.logo {
                // The one row in this list that is not a grey glyph: `.secondary`
                // is the convention here and a drawn mark cannot take it, so
                // this one carries its own colours — which the dot to its left
                // already does. Simplified for the reason it is on the island,
                // and for one more: the bubble behind is white, and the Settings
                // window's own background in light mode very nearly is too.
                logo.view(side: 13, detail: .simplified)
                    .frame(width: 16)
            } else {
                Image(systemName: def?.icon ?? act?.icon ?? "circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 16)
            }
            Text(def?.name ?? act?.title ?? button.action)
                .font(.system(size: 12))
            Spacer()
            Picker("", selection: sideBinding(button)) {
                ForEach(IslandEdgeSide.allCases, id: \.self) { side in
                    Text(side.rawValue.capitalized).tag(side)
                }
            }
            .labelsHidden()
            .frame(width: 92)
            Button {
                move(button, by: -1)
            } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless)
            Button {
                move(button, by: 1)
            } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
            Button {
                write(buttons.filter { $0.id != button.id })
            } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
        }
    }

    private func sideBinding(_ button: IslandEdgeButton) -> Binding<IslandEdgeSide> {
        Binding(
            get: { button.side },
            set: { side in
                write(buttons.map { $0.id == button.id ? IslandEdgeButton($0.action, side) : $0 })
            }
        )
    }

    private func add(_ id: String) {
        // Whichever side has fewer, so a ring fills out evenly without asking.
        let left = IslandEdgeLayout.buttons(buttons, on: .left).count
        let right = IslandEdgeLayout.buttons(buttons, on: .right).count
        write(buttons + [IslandEdgeButton(id, left <= right ? .left : .right)])
    }

    /// Moves a button within its own side. Order inside a side is the order in
    /// the list, so this is a swap with the neighbour that shares its side.
    private func move(_ button: IslandEdgeButton, by delta: Int) {
        var list = buttons
        guard let i = list.firstIndex(where: { $0.id == button.id }) else { return }
        let neighbours = list.indices.filter { list[$0].side == button.side }
        guard let at = neighbours.firstIndex(of: i) else { return }
        let to = at + delta
        guard to >= 0, to < neighbours.count else { return }
        list.swapAt(i, neighbours[to])
        write(list)
    }

    private func write(_ list: [IslandEdgeButton]) {
        state.islandEdgeButtons = list
    }
}
