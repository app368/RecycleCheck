import Foundation

// MARK: - Черновики пунктов из ответа города
// Ответ команды сайта — свободный текст. Claude превращает его в пункты
// того же вида, что пункты сайта: можно/нельзя + что именно + цитата.
// Пользователь просматривает черновики и сохраняет (CityReplyView).
// Цитата обязана дословно встречаться в письме — иначе пункт отбрасывается:
// ответ приложения всегда опирается на слова города, а не на пересказ ИИ.

final class CityAnswerExtractionService {

    static let shared = CityAnswerExtractionService()

    private init() {}

    enum ExtractionError: LocalizedError {
        case noRules

        var errorDescription: String? {
            "No rules found in this reply. It should say whether the item can go in the recycling bin."
        }
    }

    // MARK: - Публичный API

    /// Черновики пунктов из текста ответа.
    /// - Parameters:
    ///   - reply: текст письма от команды сайта
    ///   - item: предмет, о котором спрашивали
    ///   - historyEntryID: проверка, по которой был задан вопрос
    func draftRules(fromReply reply: String, item: RecycleItem, historyEntryID: UUID) async throws -> [CityAnswerRule] {
        let prompt = buildPrompt(reply: reply, item: item)
        let rawText = try await sendRequest(prompt: prompt)
        let drafts = try parseDrafts(from: rawText)

        // Только пункты с дословной цитатой из письма
        let rules = drafts.compactMap { draft -> CityAnswerRule? in
            guard let verdict = RuleVerdict(rawValue: draft.verdict),
                  !draft.item.isEmpty,
                  Self.normalized(reply).contains(Self.normalized(draft.quote)) else { return nil }
            return CityAnswerRule(itemText: draft.item, verdict: verdict,
                                  quote: draft.quote, historyEntryID: historyEntryID)
        }
        guard !rules.isEmpty else { throw ExtractionError.noRules }
        return rules
    }

    // MARK: - Промпт

    private func buildPrompt(reply: String, item: RecycleItem) -> String {
        let recognition = item.recognition
        let usedFor = (recognition?.contentsUse ?? [])
            .filter { $0.lowercased() != "n/a" }
            .joined(separator: ", ")

        return """
        A recycling program's team answered a resident's question about one item. \
        Turn the answer into rules for a recycling checklist.

        ITEM ASKED ABOUT:
        - name: \(recognition?.displayName ?? "unknown")
        - material: \(recognition?.material ?? "unknown")
        - form / type: \(recognition?.itemType ?? "unknown")
        - used for: \(usedFor.isEmpty ? "unknown" : usedFor)

        THE TEAM'S ANSWER:
        \"\"\"
        \(reply)
        \"\"\"

        Create one rule per statement in the answer about whether something may go \
        in the household RECYCLING bin:
        - "verdict": "allowed" or "not_allowed". Garbage, compost or a drop-off \
        elsewhere means "not_allowed" for the recycling bin.
        - "item": a short general name of the items the statement covers, written \
        like a recycling list entry (e.g. "all-metal kitchen utensils"). Generalize \
        from the asked item only as far as the answer itself allows.
        - "quote": the sentence from the answer that supports the rule, copied \
        character-for-character.
        Skip greetings, thanks and anything that does not say what may or may not go \
        in the recycling bin. If there is no such statement, return an empty list.

        Respond with ONLY a JSON object, no other text:
        {"rules": [{"verdict": "allowed" | "not_allowed", "item": "...", "quote": "..."}]}
        """
    }

    // MARK: - Запрос к Claude API

    private func sendRequest(prompt: String) async throws -> String {
        guard let url = URL(string: AppConfig.visionAPIEndpoint) else {
            throw NSError(domain: "CityAnswerExtractionService", code: -1)
        }

        let requestBody: [String: Any] = [
            "model": "claude-sonnet-5",
            // Thinking выключен: ответ — короткий JSON
            "thinking": ["type": "disabled"],
            "max_tokens": 1024,
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
            throw NSError(domain: "CityAnswerExtractionService", code: code)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw NSError(domain: "CityAnswerExtractionService", code: -1)
        }
        return text
    }

    // MARK: - Разбор ответа

    private struct RawDraft: Decodable {
        let verdict: String
        let item: String
        let quote: String
    }

    private struct RawDrafts: Decodable {
        let rules: [RawDraft]
    }

    /// Модель иногда пишет рассуждение перед JSON — берём текст
    /// от первой «{» до последней «}» (внутри есть вложенные объекты)
    private func parseDrafts(from rawText: String) throws -> [RawDraft] {
        guard let open = rawText.firstIndex(of: "{"),
              let close = rawText.lastIndex(of: "}"),
              open < close,
              let data = String(rawText[open...close]).data(using: .utf8) else {
            throw NSError(domain: "CityAnswerExtractionService", code: -2)
        }
        return try JSONDecoder().decode(RawDrafts.self, from: data).rules
    }

    /// Пробелы и переносы схлопываются: в письмах бывают двойные пробелы
    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
