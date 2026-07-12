import SwiftUI

struct MarkdownContentView: View {
    let markdown: String

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks.indices, id: \.self) { index in
                blockView(blocks[index])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            inlineText(text)
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case .heading(let level, let text):
            inlineText(text)
                .font(headingFont(level))
                .padding(.top, level <= 2 ? 5 : 2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle()
                            .fill(AppTheme.accentBlue.opacity(0.75))
                            .frame(width: 5, height: 5)
                            .alignmentGuide(.firstTextBaseline) { dimensions in
                                dimensions[VerticalAlignment.center]
                            }

                        inlineText(items[index])
                            .font(.body)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 9) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(items[index].marker)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(AppTheme.accentBlue)
                            .frame(minWidth: 19, alignment: .trailing)

                        inlineText(items[index].text)
                            .font(.body)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 11) {
                Capsule()
                    .fill(AppTheme.accentViolet.opacity(0.55))
                    .frame(width: 3)

                inlineText(text)
                    .font(.body.italic())
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)

        case .code(let language, let code):
            VStack(alignment: .leading, spacing: 0) {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 9)
                        .padding(.bottom, 5)
                }

                ScrollView(.horizontal) {
                    Text(code)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }

        case .divider:
            Divider()
                .padding(.vertical, 3)
        }
    }

    private func inlineText(_ source: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        let attributed = (try? AttributedString(markdown: source, options: options))
            ?? AttributedString(source)
        return Text(attributed)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1:
            return .title2.weight(.semibold)
        case 2:
            return .title3.weight(.semibold)
        default:
            return .headline
        }
    }
}

private enum MarkdownBlock {
    struct OrderedItem {
        var marker: String
        var text: String
    }

    case paragraph(String)
    case heading(level: Int, text: String)
    case unorderedList([String])
    case orderedList([OrderedItem])
    case quote(String)
    case code(language: String?, text: String)
    case divider
}

private enum MarkdownBlockParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var unorderedItems: [String] = []
        var orderedItems: [MarkdownBlock.OrderedItem] = []
        var quoteLines: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func flushUnorderedList() {
            guard !unorderedItems.isEmpty else { return }
            blocks.append(.unorderedList(unorderedItems))
            unorderedItems.removeAll(keepingCapacity: true)
        }

        func flushOrderedList() {
            guard !orderedItems.isEmpty else { return }
            blocks.append(.orderedList(orderedItems))
            orderedItems.removeAll(keepingCapacity: true)
        }

        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            blocks.append(.quote(quoteLines.joined(separator: " ")))
            quoteLines.removeAll(keepingCapacity: true)
        }

        func flushAll() {
            flushParagraph()
            flushUnorderedList()
            flushOrderedList()
            flushQuote()
        }

        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushAll()

                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                index += 1

                while index < lines.count {
                    let candidate = lines[index]
                    if candidate.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        break
                    }
                    codeLines.append(candidate)
                    index += 1
                }

                blocks.append(
                    .code(
                        language: language.isEmpty ? nil : language,
                        text: codeLines.joined(separator: "\n")
                    )
                )
                index += 1
                continue
            }

            if trimmed.isEmpty {
                flushAll()
                index += 1
                continue
            }

            if isDivider(trimmed) {
                flushAll()
                blocks.append(.divider)
                index += 1
                continue
            }

            if let heading = heading(from: trimmed) {
                flushAll()
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushUnorderedList()
                flushOrderedList()
                quoteLines.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                index += 1
                continue
            }

            if let item = unorderedItem(from: trimmed) {
                flushParagraph()
                flushOrderedList()
                flushQuote()
                unorderedItems.append(item)
                index += 1
                continue
            }

            if let item = orderedItem(from: trimmed) {
                flushParagraph()
                flushUnorderedList()
                flushQuote()
                orderedItems.append(item)
                index += 1
                continue
            }

            if rawLine.first?.isWhitespace == true {
                if !unorderedItems.isEmpty {
                    unorderedItems[unorderedItems.count - 1] += " " + trimmed
                    index += 1
                    continue
                }

                if !orderedItems.isEmpty {
                    orderedItems[orderedItems.count - 1].text += " " + trimmed
                    index += 1
                    continue
                }

                if !quoteLines.isEmpty {
                    quoteLines.append(trimmed)
                    index += 1
                    continue
                }
            }

            flushUnorderedList()
            flushOrderedList()
            flushQuote()
            paragraphLines.append(trimmed)
            index += 1
        }

        flushAll()
        return blocks.isEmpty ? [.paragraph(source)] : blocks
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let hashCount = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashCount) else { return nil }

        let remainder = line.dropFirst(hashCount)
        guard remainder.first?.isWhitespace == true else { return nil }
        return (hashCount, remainder.trimmingCharacters(in: .whitespaces))
    }

    private static func unorderedItem(from line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    private static func orderedItem(from line: String) -> MarkdownBlock.OrderedItem? {
        guard let punctuationIndex = line.firstIndex(where: { $0 == "." || $0 == ")" }) else {
            return nil
        }

        let number = String(line[..<punctuationIndex])
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }

        let afterPunctuation = line.index(after: punctuationIndex)
        guard afterPunctuation < line.endIndex, line[afterPunctuation].isWhitespace else { return nil }

        let textStart = line.index(after: afterPunctuation)
        let text = String(line[textStart...]).trimmingCharacters(in: .whitespaces)
        return MarkdownBlock.OrderedItem(marker: number + ".", text: text)
    }

    private static func isDivider(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        return compact.count >= 3 && (
            compact.allSatisfy { $0 == "-" }
                || compact.allSatisfy { $0 == "*" }
                || compact.allSatisfy { $0 == "_" }
        )
    }
}
