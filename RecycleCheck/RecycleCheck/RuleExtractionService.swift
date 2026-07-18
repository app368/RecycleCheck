import Foundation

// MARK: - AI-экстрактор правил (П2.3)
// Отправляет структурированный контент страницы (PageContentExtractor)
// в Claude API и получает пункты базы правил: allowed/not_allowed для бака
// переработки, условия, подготовка, дословная цитата-происхождение.
// База охватывает только переработку — компост и мусор не извлекаются.
// Экстрактор консервативен: пункт создаётся, только если из одной цитаты
// можно ответить «класть ли X в бак переработки?»; сомнение → пункт не создаётся.
// После разбора каждая цитата проверяется на дословность по блокам страницы;
// пункты с недословными цитатами отбрасываются (fail-safe).
// Промпт отлажен на стенде (страницы Portland + EPA): дословность цитат
// проверяется автоматически, на страницах без правил пунктов не создаётся.

final class RuleExtractionService {

    nonisolated static let shared = RuleExtractionService()

    private init() {}

    // MARK: - Ошибки сервиса

    enum ExtractionError: LocalizedError {
        case emptyContent
        case apiRequestFailed(String)
        case invalidResponse
        case parsingFailed(String)

        var errorDescription: String? {
            switch self {
            case .emptyContent:
                return "Page has no extractable content"
            case .apiRequestFailed(let detail):
                return "AI request failed: \(detail)"
            case .invalidResponse:
                return "Invalid AI response"
            case .parsingFailed(let detail):
                return "Failed to process the website data: \(detail)"
            }
        }
    }

    // MARK: - Публичный API

    /// Извлекает пункты правил из HTML одной страницы.
    /// - Parameters:
    ///   - html: HTML-контент страницы
    ///   - pageURL: URL страницы (попадает в origin пунктов)
    /// - Returns: пункты с дословными цитатами; пустой массив,
    ///   если нормативных правил на странице нет
    nonisolated func extractRules(fromHTML html: String, pageURL: String) async throws -> [RuleEntry] {

        // Извлекаем блоки контента
        let blocks = PageContentExtractor.extractBlocks(from: html)
        guard !blocks.isEmpty else {
            throw ExtractionError.emptyContent
        }

        // Формируем промпт и отправляем в Claude
        let prompt = buildPrompt(
            pageContent: PageContentExtractor.renderForPrompt(blocks),
            pageURL: pageURL
        )
        let rawResponse = try await sendRequest(prompt: prompt)

        // Парсим ответ и проверяем дословность цитат
        let rawEntries = try parseEntries(from: rawResponse)
        return makeVerifiedEntries(from: rawEntries, blocks: blocks, pageURL: pageURL)
    }

    // MARK: - Промпт экстрактора (стендовая версия v2)

    private nonisolated func buildPrompt(pageContent: String, pageURL: String) -> String {
        """
        You are extracting recycling rules from one page of a recycling website into a structured database.

        PAGE URL: \(pageURL)

        The PAGE CONTENT below consists of marked blocks:
        - "=== SECTION: X ===" is a heading; blocks after it belong to that section until the next heading
        - [list] is a list item, [prose] is a paragraph, [image] is an image alt text or caption

        YOUR TASK: extract NORMATIVE rules — statements that directly say whether specific items or materials are allowed or not allowed in the household RECYCLING bin.

        THE CONSERVATIVE TEST: create an entry ONLY if the quoted text alone answers the question "may I put X into the recycling bin?" for a concrete item or material. If a statement merely explains WHY something is accepted or not, describes benefits, statistics, the recycling process, service logistics, rates, or anything else — do NOT create an entry. When in doubt — skip. A missed rule is safer than an invented one.

        Each entry is a JSON object:
        - "material": the main material the rule is about (glass, plastic, paper, metal, cardboard, food, electronics, batteries, textiles, ...), lowercase; null if the rule names items without a clear single material
        - "item_text": short normative text naming the accepted/rejected items, near-verbatim from the quote, without explanations
        - "verdict": "allowed" or "not_allowed" — allowed or not allowed in the recycling bin
        - "conditions": array of strings — conditions limiting the rule (e.g. "only if clean and dry"); [] if none
        - "preparation": array of strings — preparation steps attached to this rule (e.g. "rinse", "remove caps"); [] if none
        - "origin": {"quote": "...", "section": "...", "source_form": "..."}
          - "quote": a VERBATIM quote copied character-for-character from ONE block (without its [list]/[prose]/[image] marker)
          - "section": the section title this block belongs to, "" if none
          - "source_form": "list", "prose" or "image_caption" matching the block marker

        STRICT RULES:
        - Extract ONLY rules about the RECYCLING bin. Statements about what belongs in compost or garbage are NOT entries — skip them entirely, even if normative. The ONLY exception: a statement that an item does NOT belong in the recycling bin is a valid "not_allowed" entry, whatever page or section it appears on.
        - The quote must be an exact substring of one single block. Never merge text from different blocks. Never paraphrase inside the quote.
        - ALL fields of an entry derive from its origin block alone. Never build item_text from one block and the quote from another.
        - item_text names the items only — never include explanation clauses (why it is dangerous, what it damages, deposit refunds etc.) even if the quote contains them.
        - Explanations, educational text, "why" reasoning, contact info, collection schedules, rates → never become entries.
        - If a block only re-explains a rule already extracted from another block of this page (e.g. a "why" section repeating the same items), skip it — do not create a duplicate entry. Keep the entry whose block states the rule normatively.
        - One block = at most one entry. Never split one sentence into several entries.
        - Handling instructions that do not decide acceptance (e.g. "set the bin at the curb by 6 am") are not entries.
        - Preparation attached to an acceptance rule ("rinse containers before recycling") goes into "preparation" of that rule. Instructions about HOW to contain or bag items (bin liners, bags for collecting scraps) are preparation of the related rule, never standalone entries.
        - An [image] block that enumerates items (e.g. "glass bottles and jars") IS a valid source with source_form "image_caption".
        - One entry per normative statement. An enumeration in one quote stays one entry.
        - "material" must be a material or waste-category word; if the items span several materials or the material is unclear, use null — never turn the item name itself into a material.

        OUTPUT: strictly a JSON array of entries, no markdown, no other text. Compact JSON without indentation. If the page contains no normative rules, output [].

        PAGE CONTENT:
        \(pageContent)
        """
    }

    // MARK: - Отправка запроса в Claude API

    /// Отправляет промпт в Claude API и возвращает сырой текстовый ответ.
    /// max_tokens = 16000: страница со множеством списков даёт до ~60 пунктов
    private nonisolated func sendRequest(prompt: String) async throws -> String {
        guard let url = URL(string: AppConfig.visionAPIEndpoint) else {
            throw ExtractionError.apiRequestFailed("Invalid API endpoint")
        }

        let requestBody: [String: Any] = [
            "model": "claude-sonnet-5",
            // Thinking выключен: парсер ждёт JSON в первом блоке ответа
            "thinking": ["type": "disabled"],
            "max_tokens": 16000,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.visionAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ExtractionError.apiRequestFailed("HTTP status \(code)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw ExtractionError.invalidResponse
        }

        // Ответ, обрезанный по max_tokens, дал бы битый JSON — отсекаем явно
        if let stopReason = json["stop_reason"] as? String, stopReason == "max_tokens" {
            throw ExtractionError.invalidResponse
        }

        return text
    }

    // MARK: - Разбор ответа

    /// Сырой пункт из JSON-ответа Claude (формат API, snake_case)
    private struct RawEntry: Decodable {
        let material: String?
        let itemText: String
        let verdict: String
        let conditions: [String]
        let preparation: [String]
        let origin: RawOrigin

        struct RawOrigin: Decodable {
            let quote: String
            let section: String
            let sourceForm: String

            enum CodingKeys: String, CodingKey {
                case quote, section
                case sourceForm = "source_form"
            }
        }

        enum CodingKeys: String, CodingKey {
            case material, verdict, conditions, preparation, origin
            case itemText = "item_text"
        }
    }

    /// Очищает ответ от возможных markdown-обёрток и парсит массив пунктов
    private nonisolated func parseEntries(from rawText: String) throws -> [RawEntry] {
        let cleaned = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw ExtractionError.parsingFailed("Cannot encode response to UTF-8")
        }

        do {
            return try JSONDecoder().decode([RawEntry].self, from: jsonData)
        } catch {
            throw ExtractionError.parsingFailed(
                "JSON decode error: \(error.localizedDescription). Raw: \(cleaned.prefix(200))"
            )
        }
    }

    // MARK: - Проверка и сборка пунктов

    /// Превращает сырые пункты в RuleEntry, отбрасывая ненадёжные:
    /// цитата обязана быть дословной подстрокой одного из блоков страницы,
    /// enum-поля — иметь известные значения. Ошибки уходят в безопасный исход:
    /// отброшенный пункт означает «информации нет», а не ложный вердикт
    private nonisolated func makeVerifiedEntries(
        from rawEntries: [RawEntry],
        blocks: [ContentBlock],
        pageURL: String
    ) -> [RuleEntry] {
        rawEntries.compactMap { raw in
            // Дословность цитаты
            guard !raw.origin.quote.isEmpty,
                  blocks.contains(where: { $0.text.contains(raw.origin.quote) }) else {
                return nil
            }

            // Известные значения enum-полей
            guard let verdict = RuleVerdict(rawValue: raw.verdict),
                  let sourceForm = RuleSourceForm(rawValue: raw.origin.sourceForm) else {
                return nil
            }

            return RuleEntry(
                material: raw.material,
                itemText: raw.itemText,
                verdict: verdict,
                conditions: raw.conditions,
                preparation: raw.preparation,
                origin: RuleOrigin(
                    quote: raw.origin.quote,
                    pageURL: pageURL,
                    section: raw.origin.section,
                    sourceForm: sourceForm
                )
            )
        }
    }
}
