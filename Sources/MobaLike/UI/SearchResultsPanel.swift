import SwiftUI

/// 底部搜索栏：输入关键词 → 生成命中列表，点击跳转到对应行
struct SearchResultsPanel: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索终端输出，回车或等待片刻列出结果", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { runSearch() }
                    .onChange(of: query) { _, newValue in
                        debouncedSearch(newValue)
                    }
                Text("\(model.searchHits.count) 条")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 46, alignment: .trailing)
                Button(action: runSearch) {
                    Image(systemName: "arrow.clockwise.circle")
                }
                .help("重新搜索")
                Button {
                    model.searchPanelVisible = false
                    model.searchHits = []
                    model.focusSelectedTerminal()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .help("关闭搜索")
            }
            .padding(6)

            if !model.searchHits.isEmpty {
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(model.searchHits) { hit in
                            Button {
                                model.jumpToSearchHit(hit)
                            } label: {
                                HStack(alignment: .top, spacing: 6) {
                                    Text("行 \(hit.lineNumber)")
                                        .font(.system(size: 11).monospaced())
                                        .foregroundColor(.accentColor)
                                        .frame(width: 64, alignment: .trailing)
                                    Text(hit.text)
                                        .font(.system(size: 12).monospaced())
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 2)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 170)
            } else if !query.trimmingCharacters(in: .whitespaces).isEmpty, model.searchHits.isEmpty, !model.recentlySearched {
                Text("无匹配结果")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(8)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .onAppear {
            focused = true
            model.searchHits = []
            query = ""
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchField)) { _ in
            focused = true
            model.searchHits = []
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private func runSearch() {
        searchTask?.cancel()
        model.searchQuery = query
        model.recentlySearched = true
        model.performSearch()
        model.focusSelectedTerminal()
    }

    private func debouncedSearch(_ newQuery: String) {
        searchTask?.cancel()
        let q = newQuery
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            model.searchQuery = q
            model.recentlySearched = true
            model.performSearch()
        }
    }
}
