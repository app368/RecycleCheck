import Foundation

// MARK: - Сервис вердикта по базе списков (П3, гибридная проверка)
// Определяет пригодность предмета к переработке по заранее собранной
// базе правил сайта (SiteRulesBuilder, П2). Сайт при проверке НЕ читается.
//
// Claude находит в обоих списках пункты, совпадающие с предметом
// по смыслу: «mug» ↔ «drinkware», «container» ≠ «bottle/jar» — этого
// не умеет сравнение строк. Решение по найденным пунктам принимает
// код (makeResult): только «можно» → да; только «нельзя» → нет;
// оба списка → да, с исключениями; ничего → неясно.
//
// Fail-safe: ошибка сети или разбора → «неясно», а не ложный вердикт.
// Нет собранной базы → отдельная ошибка (пользователю предложить Update).

final class VerdictService {

    static let shared = VerdictService()

    private init() {}

    // MARK: - Ошибки сервиса

    enum VerdictError: LocalizedError {
        case noRulesBase

        var errorDescription: String? {
            switch self {
            case .noRulesBase:
                return "No recycling data yet. Open Settings and tap \"Update recycling data\" to read the website."
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

        // Claude ищет пункты, совпадающие с предметом по смыслу
        let prompt = buildPrompt(recognition: recognition, entries: rules.entries)

        let indices: [Int]
        do {
            let rawResponse = try await sendRequest(prompt: prompt)
            indices = try parseMatches(from: rawResponse)
        } catch {
            // Fail-safe: сеть или разбор подвели — отдаём «неясно»,
            // а не ложный вердикт
            return SearchResult(status: .notFound)
        }

        // Индексы → пункты базы; невалидные и повторы отбрасываются
        let matches = Array(Set(indices))
            .sorted()
            .filter { rules.entries.indices.contains($0) }
            .map { rules.entries[$0] }
        return makeResult(from: matches)
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
        You find which rules from a recycling website's list refer to a given \
        item, using ONLY the rules list below.

        ITEM TO CHECK:
        - name: \(recognition.displayName)
        - material: \(recognition.material)
        - form / type: \(recognition.itemType)
        - used for: \(usedFor.isEmpty ? "unknown" : usedFor)

        RULES LIST (each line: [index] allowed|not_allowed: item text):
        \(rulesBlock)
        HOW TO MATCH:
        1. A rule matches if its items semantically cover THIS kind of item. \
        Use meaning, not word overlap: e.g. a "mug" is covered by "drinking \
        glasses, dishware, or drinkware"; a food-storage "container" is NOT a \
        "bottle" or "jar".
        2. The item's FORM must genuinely match. Sharing only a material is NOT \
        a match: glass being accepted as "bottles and jars" does NOT cover a \
        glass "container" or a glass "mug".
        3. Include ALL matching rules from BOTH lists. A not_allowed rule that \
        names a narrower variant of the same item (e.g. "plastic bottles that \
        held motor oil" for a plastic bottle) also matches.
        4. A rule that excludes everything EXCEPT certain shapes (e.g. "any \
        plastic that is not shaped like a bottle") does NOT match an item of \
        an allowed shape.
        5. If you are not sure that a rule covers the item, leave it out. If no \
        rule covers the item, return an empty list.

        Respond with ONLY a JSON object, no other text:
        {"matches": [<indices of all matching rules>]}
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
            "max_tokens": 300,
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

    /// Ответ модели: индексы пунктов, совпавших с предметом по смыслу
    private struct RawMatches: Decodable {
        let matches: [Int]
    }

    private func parseMatches(from rawText: String) throws -> [Int] {
        let cleaned = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw NSError(domain: "VerdictService", code: -2)
        }
        return try JSONDecoder().decode(RawMatches.self, from: jsonData).matches
    }

    // MARK: - Сборка результата

    /// Решение по пунктам, найденным Claude:
    /// только «можно» → Recyclable; только «нельзя» → Not recyclable;
    /// оба списка → Recyclable, with exceptions (пункты «нельзя» идут
    /// в исключения); ничего → «неясно»
    private func makeResult(from matches: [RuleEntry]) -> SearchResult {
        let allowed = matches.filter { $0.verdict == .allowed }
        let notAllowed = matches.filter { $0.verdict == .notAllowed }

        switch (mainEntry(of: allowed), mainEntry(of: notAllowed)) {
        case let (allowedEntry?, nil):
            return makeSearchResult(.recyclable, mainEntry: allowedEntry)
        case let (nil, notAllowedEntry?):
            return makeSearchResult(.notRecyclable, mainEntry: notAllowedEntry)
        case let (allowedEntry?, _?):
            var result = makeSearchResult(.recyclableWithExceptions, mainEntry: allowedEntry)
            result.confirmation?.exceptions = makeCitations(from: notAllowed)
            return result
        case (nil, nil):
            return SearchResult(status: .notFound)
        }
    }

    /// Главный пункт списка — самый короткий, то есть самый прямой
    /// («plastic bottles», а не «plastic bottles, tubs and jugs»)
    private func mainEntry(of entries: [RuleEntry]) -> RuleEntry? {
        entries.min { $0.itemText.count < $1.itemText.count }
    }

    /// Результат со статусом и подтверждением из главного пункта
    private func makeSearchResult(_ status: RecycleStatus, mainEntry entry: RuleEntry) -> SearchResult {
        SearchResult(
            status: status,
            sourceURL: entry.origin.pageURL,
            confirmation: Confirmation(
                citation: entry.origin.quote,
                sourceSection: section(of: entry)
            )
        )
    }

    /// Цитаты исключений: по одной на каждый уникальный пункт «нельзя»
    private func makeCitations(from entries: [RuleEntry]) -> [RuleCitation] {
        var seenQuotes = Set<String>()
        return entries.compactMap { entry in
            guard seenQuotes.insert(entry.origin.quote).inserted else { return nil }
            return RuleCitation(citation: entry.origin.quote, sourceSection: section(of: entry))
        }
    }

    /// Секция сайта пункта; nil — секции нет
    private func section(of entry: RuleEntry) -> String? {
        entry.origin.section.isEmpty ? nil : entry.origin.section
    }
}
