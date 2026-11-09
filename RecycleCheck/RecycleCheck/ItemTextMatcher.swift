import Foundation

// MARK: - Первый круг проверки: точное совпадение по тексту (гибридный вердикт)
// Ищет пункты базы, в которых слова названия предмета стоят ПОДРЯД, как фраза.
// Без ИИ: быстро, бесплатно, предсказуемо. Не нашлось — вердикт уходит
// на второй круг (смысловое сопоставление у Claude, VerdictService).
//
// Слова сравниваются без учёта регистра и единственного/множественного
// числа: «plastic bottle» находится в «plastic bottles» и в «plastic
// bottles that held motor oil». Совпадение — только фразой: «plastic can»
// не находится в «plastic 6-pack can holders», «metal can» — в «metal
// paint cans». Такие случаи, как и «glass jar» в «glass bottles and
// jars», уходят на второй круг — ИИ разберёт их по смыслу.
//
// Пункты с отрицанием («Any plastic that is not shaped like a bottle»)
// текстом не разобрать: в них есть те же слова, но смысл обратный.
// Если такой пункт среди совпавших — первый круг не решает сам.

enum ItemTextMatcher {

    /// Служебные слова — не участвуют в сравнении
    private static let stopWords: Set<String> = [
        "a", "an", "the", "of", "and", "or", "for", "with", "in", "on", "no"
    ]

    /// Слова-отрицания: пункт с ними оставляем второму кругу
    private static let negationWords: Set<String> = [
        "not", "except", "unless", "non"
    ]

    // MARK: - Публичный API

    /// Уверенные совпадения первого круга.
    /// - Returns: совпавшие пункты базы; nil — уверенного совпадения нет
    ///   (ничего не нашлось или среди найденного есть пункт с отрицанием),
    ///   нужен второй круг
    static func confidentMatches(for itemName: String, in entries: [RuleEntry]) -> [RuleEntry]? {
        let matches = matchingEntries(for: itemName, in: entries)
        guard !matches.isEmpty, !matches.contains(where: hasNegation) else {
            return nil
        }
        return matches
    }

    // MARK: - Сравнение

    /// Пункты базы, в которых слова названия предмета стоят подряд
    private static func matchingEntries(for itemName: String, in entries: [RuleEntry]) -> [RuleEntry] {
        let itemWords = normalizedWords(itemName)
        guard !itemWords.isEmpty else { return [] }
        return entries.filter { containsPhrase(itemWords, in: normalizedWords($0.itemText)) }
    }

    /// Есть ли в тексте пункта слова фразы подряд, в том же порядке
    private static func containsPhrase(_ phrase: [String], in words: [String]) -> Bool {
        guard words.count >= phrase.count else { return false }
        return (0...(words.count - phrase.count)).contains { start in
            Array(words[start..<(start + phrase.count)]) == phrase
        }
    }

    /// Есть ли в тексте пункта отрицание
    private static func hasNegation(_ entry: RuleEntry) -> Bool {
        let words = entry.itemText.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
        return words.contains { negationWords.contains($0) }
    }

    // MARK: - Нормализация

    /// Слова текста в едином виде и в исходном порядке: нижний регистр,
    /// без знаков препинания, без служебных слов, в единственном числе
    private static func normalizedWords(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) }
            .map(singular)
    }

    /// Простое приведение к единственному числу по окончанию:
    /// jars → jar, boxes → box, glasses → glass, batteries → battery.
    /// Применяется к обеим сторонам сравнения, поэтому неточности
    /// (clothes → clothe) не мешают — слова приводятся одинаково
    private static func singular(_ word: String) -> String {
        if word.hasSuffix("ies"), word.count > 4 {
            return String(word.dropLast(3)) + "y"
        }
        for ending in ["sses", "xes", "ches", "shes"] where word.hasSuffix(ending) {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), word.count > 3 {
            return String(word.dropLast())
        }
        return word
    }
}
