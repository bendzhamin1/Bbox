import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    let onPaste: (ClipItem) -> Void
    let onClose: () -> Void

    @State private var query: String = ""
    @State private var selection: Int = 0
    @FocusState private var searchFocused: Bool

    private var results: [ClipItem] {
        store.filtered(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            list
            footer
        }
        .frame(width: PanelController.panelWidth, height: PanelController.panelHeight)
        .background(glassBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .onAppear {
            selection = 0
            searchFocused = true
        }
    }

    // MARK: - Liquid glass background

    private var glassBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
            // Subtle top highlight to sell the glass depth.
            LinearGradient(
                colors: [Color.white.opacity(0.10), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Буфер обмена")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                store.clearAll()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Очистить (закреплённые останутся)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Поиск…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onChange(of: query) { _, _ in selection = 0 }
                .onSubmit { paste() }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.tab) { move(1); return .handled }
                .onKeyPress(.escape) { onClose(); return .handled }
                .onKeyPress(phases: .down) { press in
                    guard press.modifiers.contains(.command),
                          let n = Int(press.characters), n >= 1, n <= 9 else {
                        return .ignored
                    }
                    pasteIndex(n - 1)
                    return .handled
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(.regularMaterial)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75))
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if results.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(results.enumerated()), id: \.element.id) { idx, item in
                            RowView(
                                item: item,
                                index: idx,
                                isSelected: idx == selection,
                                image: store.image(for: item),
                                onSelect: { selection = idx; paste() },
                                onTogglePin: { store.togglePin(item) },
                                onDelete: { store.delete(item) }
                            )
                            .id(idx)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            .onChange(of: selection) { _, newValue in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(query.isEmpty ? "История пуста" : "Ничего не найдено")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            hint("tab", "листать")
            hint("↩", "вставить")
            hint("esc", "закрыть")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.04))
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(text)
                .font(.system(size: 10))
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Actions

    private func move(_ delta: Int) {
        let count = results.count
        guard count > 0 else { return }
        selection = max(0, min(count - 1, selection + delta))
    }

    private func paste() {
        let list = results
        guard selection >= 0, selection < list.count else { return }
        onPaste(list[selection])
    }

    private func pasteIndex(_ index: Int) {
        let list = results
        guard index >= 0, index < list.count else { return }
        onPaste(list[index])
    }
}
