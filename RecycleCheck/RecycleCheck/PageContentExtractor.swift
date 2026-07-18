import Foundation

// MARK: - Извлечение структурированного контента страницы (П2.2)
// Превращает HTML страницы в последовательность блоков с сохранением структуры:
// заголовки (секции), пункты списков, проза, alt-тексты и подписи картинок.
// Навигация, шапки, футеры и скрипты отбрасываются.
// Блоки — входной материал AI-экстрактора правил (RuleExtractionService):
// из них строится текст промпта, по ним же проверяется дословность цитат.
// Логика отлажена на стенде (python-прототип, страницы Portland и EPA).

/// Один блок контента страницы
struct ContentBlock: Equatable {
    /// Тип блока
    enum BlockType: Equatable {
        case heading
        case listItem
        case prose
        case imageAlt
    }

    let type: BlockType

    /// Заголовок секции, к которой относится блок (текст последнего заголовка)
    let section: String

    /// Текст блока (очищенный, с декодированными HTML-сущностями)
    let text: String
}

// nonisolated — только static-утилиты парсинга, без UI-состояния
nonisolated final class PageContentExtractor {

    // MARK: - Настройки разбора

    /// Контейнеры, содержимое которых не относится к контенту страницы
    private static let skipContainers: Set<String> = [
        "nav", "header", "footer", "aside", "script", "style",
        "noscript", "form", "button"
    ]

    /// Значения role, помечающие служебные контейнеры
    private static let skipRoles: Set<String> = ["navigation", "banner", "contentinfo"]

    /// Блочные теги, образующие текстовые блоки
    private static let blockTags: Set<String> = [
        "p", "li", "h1", "h2", "h3", "h4", "h5", "h6",
        "figcaption", "td", "th", "caption", "summary"
    ]

    /// Минимальная длина осмысленного текста блока
    private static let minTextLength = 3

    // MARK: - Публичный API

    /// Извлекает блоки контента из HTML.
    /// Разбор — конечный автомат по токенам «тег / текст между тегами»:
    /// закрывающие теги не несут атрибутов, поэтому пропуск контейнера
    /// с role="navigation" ведётся подсчётом одноимённых вложенных тегов
    nonisolated static func extractBlocks(from html: String) -> [ContentBlock] {
        // Комментарии убираем заранее — внутри них попадаются теги
        let cleanedHTML = removeComments(from: html)

        var blocks: [ContentBlock] = []
        var currentSection = ""

        // Состояние пропуска служебного контейнера
        var skipTag: String? = nil
        var skipDepth = 0

        // Стек открытых блочных тегов с накопителями текста
        var openBlocks: [(tag: String, text: String)] = []

        // Токенизатор: тег со всеми атрибутами либо текст между тегами
        let tagPattern = "<(/?)([a-zA-Z][a-zA-Z0-9]*)((?:[^>\"']|\"[^\"]*\"|'[^']*')*)>"
        guard let tagRegex = try? NSRegularExpression(pattern: tagPattern) else { return [] }

        var cursor = cleanedHTML.startIndex

        let matches = tagRegex.matches(
            in: cleanedHTML,
            range: NSRange(cleanedHTML.startIndex..., in: cleanedHTML)
        )

        // Завершение блока: чистим текст и формируем ContentBlock
        func flush(_ entry: (tag: String, text: String)) {
            let text = normalizeWhitespace(entry.text)
            guard text.count >= minTextLength else { return }

            if entry.tag.hasPrefix("h") && entry.tag.count == 2 {
                currentSection = text
                blocks.append(ContentBlock(type: .heading, section: text, text: text))
            } else if entry.tag == "li" {
                blocks.append(ContentBlock(type: .listItem, section: currentSection, text: text))
            } else if entry.tag == "figcaption" {
                blocks.append(ContentBlock(type: .imageAlt, section: currentSection, text: text))
            } else {
                blocks.append(ContentBlock(type: .prose, section: currentSection, text: text))
            }
        }

        for match in matches {
            guard let tagRange = Range(match.range, in: cleanedHTML) else { continue }

            // Текст между предыдущим тегом и текущим — в накопитель открытого блока
            if cursor < tagRange.lowerBound, skipTag == nil, !openBlocks.isEmpty {
                let textRun = String(cleanedHTML[cursor..<tagRange.lowerBound])
                openBlocks[openBlocks.count - 1].text += decodeEntities(textRun)
            }
            cursor = tagRange.upperBound

            // Разбираем сам тег
            guard let closingRange = Range(match.range(at: 1), in: cleanedHTML),
                  let nameRange = Range(match.range(at: 2), in: cleanedHTML),
                  let attrsRange = Range(match.range(at: 3), in: cleanedHTML) else { continue }

            let isClosing = !cleanedHTML[closingRange].isEmpty
            let tag = cleanedHTML[nameRange].lowercased()
            let attrs = String(cleanedHTML[attrsRange])

            if isClosing {
                // Выход из пропускаемого контейнера
                if let activeSkip = skipTag {
                    if tag == activeSkip {
                        skipDepth -= 1
                        if skipDepth == 0 { skipTag = nil }
                    }
                    continue
                }
                // Закрытие блочного тега: ищем его в стеке с конца
                if Self.blockTags.contains(tag) {
                    for index in stride(from: openBlocks.count - 1, through: 0, by: -1)
                    where openBlocks[index].tag == tag {
                        flush(openBlocks.remove(at: index))
                        break
                    }
                }
                continue
            }

            // Открывающий тег внутри пропускаемого контейнера: считаем одноимённые
            if let activeSkip = skipTag {
                if tag == activeSkip { skipDepth += 1 }
                continue
            }

            // Вход в пропускаемый контейнер (по тегу или role)
            if Self.skipContainers.contains(tag) || Self.skipRoles.contains(attributeValue("role", in: attrs) ?? "") {
                skipTag = tag
                skipDepth = 1
                continue
            }

            // Картинка: alt-текст — самостоятельный блок
            if tag == "img" {
                if let alt = attributeValue("alt", in: attrs),
                   alt.count >= minTextLength {
                    blocks.append(ContentBlock(
                        type: .imageAlt,
                        section: currentSection,
                        text: normalizeWhitespace(decodeEntities(alt))
                    ))
                }
                continue
            }

            // Открытие блочного тега
            if Self.blockTags.contains(tag) {
                openBlocks.append((tag: tag, text: ""))
            }
        }

        return blocks
    }

    /// Текст страницы для промпта экстрактора: секции + помеченные блоки.
    /// Формат согласован с промптом RuleExtractionService
    nonisolated static func renderForPrompt(_ blocks: [ContentBlock]) -> String {
        var lines: [String] = []
        for block in blocks {
            switch block.type {
            case .heading:
                lines.append("\n=== SECTION: \(block.text) ===")
            case .listItem:
                lines.append("[list] \(block.text)")
            case .prose:
                lines.append("[prose] \(block.text)")
            case .imageAlt:
                lines.append("[image] \(block.text)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Вспомогательные методы

    /// Удаляет HTML-комментарии
    private nonisolated static func removeComments(from html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<!--[\\s\\S]*?-->") else { return html }
        return regex.stringByReplacingMatches(
            in: html,
            range: NSRange(html.startIndex..., in: html),
            withTemplate: " "
        )
    }

    /// Достаёт значение атрибута из строки атрибутов тега
    private nonisolated static func attributeValue(_ name: String, in attrs: String) -> String? {
        let pattern = "\(name)\\s*=\\s*[\"']([^\"']*)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: attrs, range: NSRange(attrs.startIndex..., in: attrs)),
              let range = Range(match.range(at: 1), in: attrs) else {
            return nil
        }
        return String(attrs[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Декодирует HTML-сущности: именованные (включая типографские)
    /// и числовые (&#8217; и &#x2019;). Цитаты пунктов показываются
    /// пользователю — сущности в них недопустимы
    private nonisolated static func decodeEntities(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&rsquo;", with: "\u{2019}")
            .replacingOccurrences(of: "&lsquo;", with: "\u{2018}")
            .replacingOccurrences(of: "&rdquo;", with: "\u{201D}")
            .replacingOccurrences(of: "&ldquo;", with: "\u{201C}")
            .replacingOccurrences(of: "&mdash;", with: "\u{2014}")
            .replacingOccurrences(of: "&ndash;", with: "\u{2013}")
            .replacingOccurrences(of: "&hellip;", with: "\u{2026}")
            .replacingOccurrences(of: "&bull;", with: "\u{2022}")

        // Числовые сущности: десятичные и шестнадцатеричные
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let matches = regex.matches(
                in: result,
                range: NSRange(result.startIndex..., in: result)
            )
            // Замены с конца — индексы предыдущих совпадений не смещаются
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                      let hexFlagRange = Range(match.range(at: 1), in: result),
                      let digitsRange = Range(match.range(at: 2), in: result) else { continue }
                let isHex = !result[hexFlagRange].isEmpty
                let digits = String(result[digitsRange])
                guard let code = UInt32(digits, radix: isHex ? 16 : 10),
                      let scalar = Unicode.Scalar(code) else { continue }
                result.replaceSubrange(fullRange, with: String(Character(scalar)))
            }
        }

        // &amp; — последним: иначе &amp;#8217; декодировался бы дважды
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Сжимает пробельные символы и обрезает края
    private nonisolated static func normalizeWhitespace(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\s+") else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: " "
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
