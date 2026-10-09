import SwiftUI

/// The clipboard tab: what you copied, searchable, with favourites.
///
/// The history lives in `ClipboardStore.shared`; this only draws it. Watching is
/// off until it is turned on here — the app does not start reading what somebody
/// copies because it was launched.
struct ClipboardView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = ClipboardStore.shared

    @State private var query = ""
    @State private var showingFavourites = false
    @FocusState private var searchFocused: Bool

    private var shown: [ClipEntry] {
        (showingFavourites ? store.favourites : store.entries).filter { $0.matches(query) }
    }

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 8) {
                header
                if store.watching {
                    list
                } else {
                    offState
                }
            }
            // The Mochi gutter, as every other card leaves it.
            .padding(.leading, 108)
            .padding(.trailing, 14)
            .padding(.vertical, 10)
        }
        // Leaving the tab gives the island its auto-close back, in case the
        // search field was still holding it open.
        .onDisappear { releaseHold() }
        .onChange(of: state.view) { _, v in if v != .clipboard { releaseHold() } }
    }

    private func releaseHold() {
        searchFocused = false
        state.isReplying = false
        state.isPinned = false
    }

    // MARK: – Header

    private var header: some View {
        HStack(spacing: 8) {
            tab("History", count: store.entries.count, on: !showingFavourites) {
                showingFavourites = false
            }
            tab("Favourites", count: store.favourites.count, on: showingFavourites) {
                showingFavourites = true
            }
            Spacer(minLength: 0)
            if store.watching {
                searchField
                Button(action: { store.clear() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                }
                .buttonStyle(.plain)
                .help("Forget everything copied")
            }
        }
    }

    private func tab(_ title: String, count: Int, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 11, weight: .medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9.5).monospacedDigit())
                        .opacity(0.7)
                }
            }
            .foregroundColor(Color(hex: on ? "#F5F6F8" : "#8E939C"))
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(on ? Color(hex: "#1D1F23") : Color.clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        TextField("Search", text: $query)
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(Color(hex: "#F5F6F8"))
            .focused($searchFocused)
            .frame(width: 130)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Color.white.opacity(searchFocused ? 0.12 : 0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            // The island closes on its own timer, which knows nothing about a
            // half-typed search. The cursor being in the field is what holds it.
            .onChange(of: searchFocused) { _, focused in
                state.isReplying = focused
                state.isPinned = focused
            }
    }

    // MARK: – Body

    private var offState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Coucou is not watching the clipboard.")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#C5C8CD"))
            Text("Turn it on and what you copy is kept here while the app runs — "
                 + "in memory only, never written to disk.")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#6B7079"))
                .fixedSize(horizontal: false, vertical: true)
            SecondaryButton("Start watching") { store.start() }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var list: some View {
        if shown.isEmpty {
            Text(query.isEmpty
                 ? (showingFavourites ? "Nothing kept yet." : "Copy something and it shows up here.")
                 : "Nothing matches.")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#6B7079"))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(shown) { entry in
                        ClipRow(entry: entry)
                    }
                }
            }
        }
    }
}

/// One copied thing. Click to put it back on the pasteboard.
private struct ClipRow: View {
    let entry: ClipEntry
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            icon
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Color(hex: "#E8E9EC"))
                    .lineLimit(1).truncationMode(.tail)
                Text(entry.subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#6B7079"))
            }
            Spacer(minLength: 4)
            if isHovered {
                Button(action: { ClipboardStore.shared.toggleFavourite(entry) }) {
                    Image(systemName: entry.favourite ? "heart.fill" : "heart")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: entry.favourite ? "#F472B6" : "#8E939C"))
                }
                .buttonStyle(.plain)
                Button(action: { ClipboardStore.shared.remove(entry) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(hex: "#8E939C"))
                }
                .buttonStyle(.plain)
            } else {
                if entry.favourite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "#F472B6"))
                }
                Text(ClipEntry.ago(entry.copiedAt))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(Color(hex: "#5F646D"))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(isHovered ? Color.white.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture { ClipboardStore.shared.copy(entry) }
        .onHover { isHovered = $0 }
    }

    @ViewBuilder private var icon: some View {
        switch entry.kind {
        case .image(let image, _):
            Image(nsImage: image)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        case .text:
            Image(systemName: entry.subtitle == "Link" ? "link" : "text.alignleft")
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#8E939C"))
                .frame(width: 20, height: 20)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}
