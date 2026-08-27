import Foundation
import SwiftTerm

/// 一次搜索命中（结果列表项）
struct TerminalSearchHit: Identifiable, Equatable {
    let id: Int        // 结果序号
    let row: Int       // 供 scrollTo(row:) 使用的滚动坐标
    let lineNumber: Int // 展示用行号（1 起）
    let text: String
}

/// 终端文本搜索：建立行索引并用 scrollTo 跳转
enum TerminalSearch {
    /// 在终端缓冲里搜索关键词（大小写不敏感），返回每条命中所在行
    static func hits(in view: TerminalView, query: String) -> [TerminalSearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        let term = view.getTerminal()

        // 探测有效行的起点 linesTop（内部字段未公开，用 getScrollInvariantLine 探测）
        var base = 0
        while term.getScrollInvariantLine(row: base) == nil, base < 100000 { base += 1 }

        var hits: [TerminalSearchHit] = []
        var i = base
        while let line = term.getScrollInvariantLine(row: i) {
            let text = line.translateToString(trimRight: true)
            if !text.isEmpty && text.lowercased().contains(q) {
                hits.append(TerminalSearchHit(id: hits.count,
                                              row: i - base,
                                              lineNumber: i - base + 1,
                                              text: text))
                if hits.count >= 500 { break }
            }
            i += 1
        }
        return hits
    }

    /// 跳转到指定行（滚动到该行并聚焦终端）
    static func jump(_ view: TerminalView?, to row: Int) {
        guard let view else { return }
        view.scrollTo(row: row)
    }
}
