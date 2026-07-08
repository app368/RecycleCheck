import Foundation

// MARK: - Умный скоринг упоминаний (СП4.1, задача «умный скоринг»)
// Правило совместной встречаемости: слово формы (itemType) получает полный
// вес только если в том же абзаце встречается материал предмета. Форма без
// материала рядом — слабый сигнал: многозначные слова формы без контекста
// материала часто оказываются шумом («container» — предмет / take-out /
// бак для сбора).
// Правило вынесено в отдельный модуль, чтобы жить в одном месте:
// сейчас используется ConfirmationCollector, СП3 — кандидат на будущее.

struct MentionScoring {

    // MARK: - Веса (стартовые значения, подбор эмпирический)

    /// Вес совпадения по материалу (главный сигнал)
    static let materialWeight = 3

    /// Вес совпадения по форме, когда материал есть в том же абзаце
    static let formWithMaterialWeight = 3

    /// Вес совпадения по форме без материала рядом (слабый сигнал)
    static let formAloneWeight = 1

    /// Вес совпадения по содержимому / назначению
    static let contentsWeight = 1

    /// Минимальная длина ключевого слова (отбрасываем предлоги и шум)
    static let minKeywordLength = 3

    // MARK: - Ключевые слова предмета по категориям

    /// Слова предмета, разложенные по категориям — категория определяет
    /// правило начисления веса
    struct Keywords {
        /// Слова материала (glass, plastic, …)
        let material: [String]

        /// Слова формы / типа предмета (bottle, container, …)
        let form: [String]

        /// Слова содержимого / назначения (beverage, food, …)
        let contents: [String]

        var isEmpty: Bool {
            material.isEmpty && form.isEmpty && contents.isEmpty
        }
    }

    /// Готовит ключевые слова из распознавания: нижний регистр,
    /// пропуск "N/A", отсев слишком коротких слов
    static func keywords(from recognition: ItemRecognition) -> Keywords {
        Keywords(
            material: words(from: recognition.material),
            form: words(from: recognition.itemType),
            contents: recognition.contentsUse.flatMap { words(from: $0) }
        )
    }

    // MARK: - Скоринг абзаца

    /// Считает релевантность абзаца по правилу совместной встречаемости.
    /// - Parameters:
    ///   - text: текст абзаца, уже приведённый к нижнему регистру
    ///   - keywords: ключевые слова предмета по категориям
    /// - Returns: суммарный вес; 0 — упоминания нет
    static func score(paragraphLowercased text: String, keywords: Keywords) -> Int {
        var score = 0

        // Материал — полный вес всегда
        var materialFound = false
        for word in keywords.material where text.contains(word) {
            score += materialWeight
            materialFound = true
        }

        // Форма — полный вес только при материале в том же абзаце
        let formWeight = materialFound ? formWithMaterialWeight : formAloneWeight
        for word in keywords.form where text.contains(word) {
            score += formWeight
        }

        // Содержимое / назначение
        for word in keywords.contents where text.contains(word) {
            score += contentsWeight
        }

        return score
    }

    // MARK: - Вспомогательное

    /// Разбивает значение поля на слова: нижний регистр, пропуск "N/A",
    /// отсев слов короче minKeywordLength
    private static func words(from field: String) -> [String] {
        guard field.lowercased() != "n/a" else { return [] }
        return field
            .lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= minKeywordLength }
    }
}
