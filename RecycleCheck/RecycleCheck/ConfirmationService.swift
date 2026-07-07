import Foundation

// MARK: - Сервис анализа упоминаний (СП4.1 «Подтверждение вердикта», шаг 2)
// Принимает собранные ConfirmationCollector упоминания и отправляет их
// в Claude AI с задачей: выбрать дословную цитату-подтверждение,
// выделить исключения и инструкции по подготовке.
// Возвращает структурированный Confirmation с тремя полями:
// citation, exceptions, preparation.

final class ConfirmationService {
    
    static let shared = ConfirmationService()
    
    private init() {}
    
    // MARK: - Ошибки сервиса
    
    enum ConfirmationError: LocalizedError {
        case noMentions
        case apiRequestFailed(String)
        case invalidResponse
        case parsingFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .noMentions:
                return "No mentions to analyze"
            case .apiRequestFailed(let detail):
                return "AI request failed: \(detail)"
            case .invalidResponse:
                return "Invalid AI response"
            case .parsingFailed(let detail):
                return "Failed to parse confirmation: \(detail)"
            }
        }
    }
    
    // MARK: - Публичный API
    
    /// Анализирует собранные упоминания и формирует структурированное подтверждение.
    /// - Parameters:
    ///   - mentions: упоминания предмета, собранные ConfirmationCollector
    ///   - recognition: распознавание предмета (нужно Claude для контекста)
    ///   - verdict: статус пригодности из СП3 (определяет логику заполнения полей)
    /// - Returns: Confirmation со структурированным ответом
    func makeConfirmation(
        from mentions: [ConfirmationCollector.Mention],
        recognition: ItemRecognition,
        verdict: RecycleStatus
    ) async throws -> Confirmation {
        
        guard !mentions.isEmpty else {
            throw ConfirmationError.noMentions
        }
        
        // Формируем промпт для Claude
        let prompt = buildPrompt(
            mentions: mentions,
            recognition: recognition,
            verdict: verdict
        )
        
        // Отправляем запрос и получаем сырой ответ
        let rawResponse = try await sendRequest(prompt: prompt)
        
        // Парсим JSON в Confirmation
        return try parseConfirmation(from: rawResponse)
    }
    
    // MARK: - Формирование промпта
    
    /// Формирует подробный промпт для Claude AI с инструкциями
    /// по выбору цитаты, исключений и инструкций по подготовке.
    private func buildPrompt(
        mentions: [ConfirmationCollector.Mention],
        recognition: ItemRecognition,
        verdict: RecycleStatus
    ) -> String {
        // Описание предмета для контекста
        let itemDescription = recognition.displayName
        
        // Текстовое описание вердикта для Claude
        let verdictText: String
        switch verdict {
        case .recyclable:
            verdictText = "RECYCLABLE"
        case .notRecyclable:
            verdictText = "NOT RECYCLABLE"
        case .notFound:
            // На notFound этот сервис вообще не должен вызываться,
            // но на всякий случай обработаем
            verdictText = "NOT FOUND"
        }
        
        // Формируем список упоминаний с нумерацией и URL источника
        var mentionsBlock = ""
        for (index, mention) in mentions.enumerated() {
            mentionsBlock += "\n[Mention \(index + 1)] (source: \(mention.sourceURL))\n"
            mentionsBlock += mention.text
            mentionsBlock += "\n"
        }
        
        // Полный промпт с чёткими инструкциями
        let prompt = """
        You are analyzing recycling website content to provide a clear, structured \
        confirmation for the user.
        
        ITEM: \(itemDescription)
        VERDICT (already determined): \(verdictText)
        
        Below are paragraphs from the recycling website where this item is mentioned. \
        Your task is to produce a JSON response with three fields: citation, exceptions, preparation.
        
        FIELD RULES:
        
        1. "citation" — a DIRECT, VERBATIM quote from the mentions that best confirms \
        the verdict. Copy the text exactly as it appears, do not paraphrase. \
        Choose the most informative and clear sentence or short passage. \
        Keep it under 300 characters when possible. \
        This field is REQUIRED.
        
        2. "exceptions" — exceptions to the verdict (e.g., "cardboard is recyclable, \
        but greasy pizza boxes are not"). \
        - If the verdict is NOT RECYCLABLE: set this field to exactly "Not applicable". \
        - If the verdict is RECYCLABLE and the mentions describe specific exceptions: \
        provide them as a direct quote OR as your own concise summary if information \
        is scattered across mentions. \
        - If the verdict is RECYCLABLE but no exceptions are mentioned anywhere: \
        set this field to exactly "No exceptions mentioned".
        
        3. "preparation" — how to prepare the item for recycling (rinse, flatten, \
        remove caps, etc.). \
        - If the verdict is NOT RECYCLABLE: set this field to exactly "Not applicable". \
        - If the verdict is RECYCLABLE and the mentions describe preparation steps: \
        provide them as your own concise summary (1-2 short sentences). \
        - If the verdict is RECYCLABLE but no preparation instructions are found: \
        set this field to exactly "No preparation instructions found".
        
        IMPORTANT:
        - Respond with ONLY a valid JSON object. No preamble, no markdown, no explanations.
        - Use double quotes for JSON strings. Escape inner quotes as \\".
        - Do NOT invent information that is not present in the mentions.
        
        RESPONSE FORMAT:
        {"citation": "...", "exceptions": "...", "preparation": "..."}
        
        MENTIONS:
        \(mentionsBlock)
        """
        
        return prompt
    }
    
    // MARK: - Отправка запроса в Claude API
    
    /// Отправляет промпт в Claude API и возвращает сырой текстовый ответ.
    /// Использует тот же endpoint и API-ключ, что и другие сервисы в проекте.
    private func sendRequest(prompt: String) async throws -> String {
        guard let url = URL(string: AppConfig.visionAPIEndpoint) else {
            throw ConfirmationError.apiRequestFailed("Invalid API endpoint")
        }
        
        // Формируем тело запроса
        let requestBody: [String: Any] = [
            // claude-sonnet-4 отключён Anthropic 15.06.2026, заменён на sonnet-5
            "model": "claude-sonnet-5",
            // У sonnet-5 thinking включён по умолчанию — выключаем:
            // парсер ждёт JSON в первом блоке ответа, и max_tokens рассчитан без thinking
            "thinking": ["type": "disabled"],
            "max_tokens": 1500,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.visionAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // Отправляем запрос
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ConfirmationError.apiRequestFailed("HTTP status \(code)")
        }
        
        // Извлекаем текст ответа из структуры Claude API
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw ConfirmationError.invalidResponse
        }
        
        return text
    }
    
    // MARK: - Парсинг JSON в Confirmation
    
    /// Очищает ответ от возможных обёрток (markdown-кодов) и парсит в Confirmation.
    private func parseConfirmation(from rawText: String) throws -> Confirmation {
        // Убираем возможные markdown-обёртки вокруг JSON
        let cleaned = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = cleaned.data(using: .utf8) else {
            throw ConfirmationError.parsingFailed("Cannot encode response to UTF-8")
        }
        
        do {
            let decoder = JSONDecoder()
            let confirmation = try decoder.decode(Confirmation.self, from: jsonData)
            return confirmation
        } catch {
            // Если парсинг не удался — даём подробное описание для отладки
            throw ConfirmationError.parsingFailed(
                "JSON decode error: \(error.localizedDescription). Raw: \(cleaned.prefix(200))"
            )
        }
    }
}
