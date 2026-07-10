import Foundation

// MARK: - Сервис вердикта по базе списков (П3)
// Ядро списочной архитектуры: определяет пригодность предмета к переработке
// ОДНИМ вопросом к Claude — «есть ли предмет в списках сайта?».
// Сайт при проверке НЕ читается: матчинг идёт против заранее собранной
// базы правил (SiteRulesBuilder, П2).
//
// Семантика сопоставления остаётся у модели: «mug» ↔ «drinkware»,
// «container» ≠ «bottle/jar» — этого не умеет сравнение строк.
//
// Три исхода: recyclable (да) / notRecyclable (нет) / notFound (неясно).
// Fail-safe: ошибка сети или разбора → «неясно», а не ложный вердикт.
// Нет собранной базы → отдельная ошибка (пользователю предложить Refresh).

final class VerdictService {

    static let shared = VerdictService()

    private init() {}

    // MARK: - Ошибки сервиса

    enum VerdictError: LocalizedError {
        case noRulesBase

        var errorDescription: String? {
            switch self {
            case .noRulesBase:
                return "No recycling rules yet. Open Settings and tap \"Refresh source pages\" to read the website."
            }
        }
    }

    // MARK: - Публичный API

    /// Определяет вердикт для предмета по сохранённой базе списков.
    /// - Parameter recognition: распознанный предмет (СП2)
    /// - Returns: SearchResult со статусом и подтверждающим пунктом (для да/нет)
    /// - Throws: VerdictError.noRulesBase, если база ещё не собрана
    func decideVerdict(for recognition: ItemRecognition) async throws -> SearchResult {

        // База списков должна быть собрана для текущего сайта
        let baseURL = AppConfig.recyclingWebsiteURL
        guard let rules = StorageService.shared.loadSiteRules(forBaseURL: baseURL),
              !rules.isEmpty else {
            throw VerdictError.noRulesBase
        }

        // Один вызов Claude: предмет против пронумерованных пунктов базы
        let prompt = buildPrompt(recognition: recognition, entries: rules.entries)

        let decision: RawDecision
        do {
            let rawResponse = try await sendRequest(prompt: prompt)
            decision = try parseDecision(from: rawResponse)
        } catch {
            // Fail-safe: сеть или разбор подвели — отдаём «неясно»,
            // а не ложный вердикт
            return SearchResult(status: .notFound)
        }

        return makeResult(from: decision, entries: rules.entries)
    }

    // MARK: - Формирование промпта

    /// Собирает промпт: описание предмета + пронумерованный список пунктов базы.
    /// Пункты подаются компактно (индекс, вердикт, текст, секция, материал) —
    /// этого достаточно для семантического сопоставления
    private func buildPrompt(recognition: ItemRecognition, entries: [RuleEntry]) -> String {
        let usedFor = recognition.contentsUse
            .filter { $0.lowercased() != "n/a" }
            .joined(separator: ", ")

        // Нумерованный список пунктов: индекс соответствует позиции в entries
        var rulesBlock = ""
        for (index, entry) in entries.enumerated() {
            let material = entry.material.map { " material=\($0)" } ?? ""
            let section = entry.origin.section.isEmpty ? "" : " section=\"\(entry.origin.section)\""
            rulesBlock += "[\(index)] \(entry.verdict.rawValue): \(entry.itemText)\(material)\(section)\n"
        }

        return """
        You decide whether an item may go in the household RECYCLING bin, \
        using ONLY the rules list from a recycling website below.

        ITEM TO CHECK:
        - name: \(recognition.displayName)
        - material: \(recognition.material)
        - form / type: \(recognition.itemType)
        - used for: \(usedFor.isEmpty ? "unknown" : usedFor)

        RULES LIST (each line: [index] allowed|not_allowed: item text):
        \(rulesBlock)
        DECISION PROCEDURE:
        1. Find the rule whose items semantically cover THIS item. Use meaning, \
        not word overlap: e.g. a "mug" is covered by "drinking glasses, dishware, \
        or drinkware"; a food-storage "container" is NOT a "bottle" or "jar".
        2. The item's FORM must genuinely match. Sharing only a material is NOT a \
        match: glass being accepted as "bottles and jars" does NOT cover a glass \
        "container" or a glass "mug".
        3. If BOTH an allowed rule and a not_allowed rule could apply, the \
        not_allowed rule WINS (exclusions override).
        4. Choose the verdict:
        - "recyclable" — the item clearly matches an allowed rule and no not_allowed rule excludes it.
        - "not_recyclable" — the item clearly matches a not_allowed rule.
        - "unclear" — the item is not clearly covered by any rule. When in doubt, choose "unclear". A wrong "recyclable"/"not_recyclable" is worse than "unclear".

        Respond with ONLY a JSON object, no other text:
        {"verdict": "recyclable" | "not_recyclable" | "unclear", "rule_index": <index of the matched rule, or null for unclear>}
        """
    }

    // MARK: - Отправка запроса в Claude API

    private func sendRequest(prompt: String) async throws -> String {
        guard let url = URL(string: AppConfig.visionAPIEndpoint) else {
            throw VerdictError.noRulesBase
        }

        let requestBody: [String: Any] = [
            "model": "claude-sonnet-5",
            // Thinking выключен: парсер ждёт JSON в первом блоке ответа
            "thinking": ["type": "disabled"],
            "max_tokens": 200,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.visionAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "VerdictService", code: code)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw NSError(domain: "VerdictService", code: -1)
        }

        return text
    }

    // MARK: - Разбор ответа

    /// Решение модели: вердикт + индекс подтверждающего пункта
    private struct RawDecision: Decodable {
        let verdict: String
        let ruleIndex: Int?

        enum CodingKeys: String, CodingKey {
            case verdict
            case ruleIndex = "rule_index"
        }
    }

    private func parseDecision(from rawText: String) throws -> RawDecision {
        let cleaned = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw NSError(domain: "VerdictService", code: -2)
        }
        return try JSONDecoder().decode(RawDecision.self, from: jsonData)
    }

    // MARK: - Сборка результата

    /// Превращает решение модели в SearchResult.
    /// Для да/нет прикрепляет подтверждение из совпавшего пункта
    /// (дословная цитата, секция, условия, подготовка, ссылка на страницу)
    private func makeResult(from decision: RawDecision, entries: [RuleEntry]) -> SearchResult {
        let status: RecycleStatus
        switch decision.verdict.lowercased() {
        case "recyclable":
            status = .recyclable
        case "not_recyclable":
            status = .notRecyclable
        default:
            // «unclear» и любые неожиданные значения — безопасный исход «неясно»
            return SearchResult(status: .notFound)
        }

        // Подтверждающий пункт по индексу; без валидного пункта — «неясно»,
        // чтобы да/нет всегда были подкреплены цитатой
        guard let index = decision.ruleIndex, entries.indices.contains(index) else {
            return SearchResult(status: .notFound)
        }
        let entry = entries[index]

        return SearchResult(
            status: status,
            sourceURL: entry.origin.pageURL,
            confirmation: makeConfirmation(from: entry)
        )
    }

    /// Строит подтверждение из совпавшего пункта базы:
    /// дословная цитата + секция сайта (концепция «простого ответа»)
    private func makeConfirmation(from entry: RuleEntry) -> Confirmation {
        Confirmation(
            citation: entry.origin.quote,
            sourceSection: entry.origin.section.isEmpty ? nil : entry.origin.section
        )
    }
}
