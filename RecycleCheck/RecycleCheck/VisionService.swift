import Foundation
import UIKit

// MARK: - Сервис распознавания изображений (СП2)
// Двухэтапное распознавание в одном API-запросе:
// Этап 1 (грубый отсев): определяет категорию — item / bulky / otherObjects / unclear
// Этап 2 (детальное): для category=item заполняет material, itemType, contentsUse
// Для остальных категорий возвращает сообщение для пользователя.

final class VisionService {
    
    static let shared = VisionService()
    
    private init() {}
    
    // MARK: - Ошибки сервиса
    
    enum VisionError: LocalizedError {
        case imageConversionFailed
        case invalidResponse
        case apiError(String)
        case networkError(Error)
        case parsingFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .imageConversionFailed:
                return "Failed to process the image"
            case .invalidResponse:
                return "Invalid response from recognition service"
            case .apiError(let message):
                return "API error: \(message)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .parsingFailed(let detail):
                return "Failed to parse recognition result: \(detail)"
            }
        }
    }
    
    // MARK: - Распознавание предмета на фото
    
    /// Отправляет изображение в Claude Vision API и возвращает
    /// результат двухэтапного распознавания.
    /// - Parameter image: фотография предмета
    /// - Returns: результат с категорией и (для item) детальным описанием
    func recognizeItem(image: UIImage) async throws -> ItemRecognition {
        
        // Конвертируем изображение в base64
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw VisionError.imageConversionFailed
        }
        let base64String = imageData.base64EncodedString()
        
        // MARK: - Формируем запрос к API
        
        let requestBody = buildRequestBody(base64Image: base64String)
        
        guard let url = URL(string: AppConfig.visionAPIEndpoint) else {
            throw VisionError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.visionAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // MARK: - Отправляем запрос
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VisionError.invalidResponse
        }
        
        // MARK: - Обрабатываем ответ
        
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw VisionError.apiError("Status \(httpResponse.statusCode): \(errorText)")
        }
        
        return try parseResponse(data: data)
    }
    
    // MARK: - Формирование тела запроса
    
    /// Собираем JSON для Claude Messages API с изображением.
    /// Промпт содержит инструкции для двухэтапного распознавания.
    private func buildRequestBody(base64Image: String) -> [String: Any] {
        return [
            // claude-sonnet-4 отключён Anthropic 15.06.2026, заменён на sonnet-5
            "model": "claude-sonnet-5",
            // У sonnet-5 thinking включён по умолчанию — выключаем:
            // парсер ждёт JSON в первом блоке ответа, и max_tokens рассчитан без thinking
            "thinking": ["type": "disabled"],
            "max_tokens": 400,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": recognitionPrompt
                        ]
                    ]
                ]
            ]
        ]
    }
    
    // MARK: - Комбинированный промпт для двухэтапного распознавания
    
    /// Инструкции для Claude Vision:
    /// Этап 1: классификация изображения (item / bulky / otherObjects / unclear)
    /// Этап 2: для item — детальное описание (material, itemType, contentsUse)
    private var recognitionPrompt: String {
        """
        You are a recycling expert. Analyze the photo and respond with ONLY a JSON object, \
        no other text, no markdown, no code fences.
        
        STEP 1 — CLASSIFY the image into one of these categories:
        - "item" — a small/medium household item, packaging, container, or disposable product \
        that could potentially be recycled or thrown away (bottles, cans, boxes, bags, cups, \
        batteries, light bulbs, wires, styrofoam, etc.)
        - "bulky" — a large household item (furniture, mattress, appliance, carpet, large electronics like TV)
        - "otherObjects" — not a disposable item (landscape, nature, animal, person, vehicle, \
        building, food without packaging, clothing being worn, tools in use)
        - "unclear" — image is too blurry, dark, or ambiguous to identify anything
        
        STEP 2 — Based on the category, respond with the appropriate JSON format:
        
        FOR "item":
        {"category":"item","material":"<material>","itemType":"<item name>","contentsUse":["<use1>","<use2>"]}
        
        Item field rules:
        - "material": primary material. Use ONLY one of: paper, plastic, glass, metal, \
        foam, fabric, organic, mixed, ceramic, rubber, wood. \
        Cardboard and cartons are "paper" (the shape goes to itemType). \
        Aluminum, steel and tin are "metal". \
        Use "N/A" if material cannot be determined (e.g. batteries, electronics).
        - "itemType": item name/shape. Examples: bottle, jar, jug, tub, bucket, can, pot, box, \
        carton, bag, foil, scrap, cup, lid, straw, utensil, hose, cord, bulb, battery, \
        styrofoam, hanger, diaper, glove. Use lowercase.
        - "contentsUse": 1-3 words for what the item holds or is designed for. \
        Examples: beverage, food, dairy, cereal, cleaning, personal care, paint, aerosol, \
        mail, plant, shipping, gift, motor oil, eggs, lighting, power. \
        Use ["N/A"] if not applicable.
        
        Focus rules for items:
        - Focus on the ITEM ITSELF, ignore the background completely.
        - SHAPE and FORM have HIGH priority for identification.
        - MATERIAL has HIGH priority.
        - Text on the item (brand names, labels) has LOW priority.
        - Do NOT describe colors, decorations, or branding.
        
        FOR "bulky":
        {"category":"bulky","message":"This appears to be a large household item. Our app focuses on everyday packaging and small items. For large item disposal options, contact your local waste management service."}
        
        FOR "otherObjects":
        {"category":"otherObjects","message":"This image doesn't appear to contain a recyclable or disposable item. Please photograph packaging, containers, or small household items."}
        
        FOR "unclear":
        {"category":"unclear","message":"We couldn't clearly identify an item in this photo. Please try taking a clearer photo with good lighting."}
        
        EXAMPLES:
        - Plastic yogurt cup: {"category":"item","material":"plastic","itemType":"tub","contentsUse":["dairy","yogurt"]}
        - Cardboard shipping box: {"category":"item","material":"paper","itemType":"box","contentsUse":["shipping"]}
        - Milk carton: {"category":"item","material":"paper","itemType":"carton","contentsUse":["dairy","beverage"]}
        - Aluminum soda can: {"category":"item","material":"metal","itemType":"can","contentsUse":["beverage"]}
        - Glass sauce jar: {"category":"item","material":"glass","itemType":"jar","contentsUse":["food","sauce"]}
        - AA battery: {"category":"item","material":"N/A","itemType":"battery","contentsUse":["N/A"]}
        - Extension cord: {"category":"item","material":"N/A","itemType":"cord","contentsUse":["power"]}
        - Couch in a room: {"category":"bulky","message":"This appears to be a large household item. Our app focuses on everyday packaging and small items. For large item disposal options, contact your local waste management service."}
        - A park with trees: {"category":"otherObjects","message":"This image doesn't appear to contain a recyclable or disposable item. Please photograph packaging, containers, or small household items."}
        - Very dark blurry photo: {"category":"unclear","message":"We couldn't clearly identify an item in this photo. Please try taking a clearer photo with good lighting."}
        """
    }
    
    // MARK: - Парсинг ответа API
    
    /// Извлекаем JSON из ответа Claude API и парсим в ItemRecognition.
    private func parseResponse(data: Data) throws -> ItemRecognition {
        // Извлекаем текст из ответа Claude API
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw VisionError.invalidResponse
        }
        
        // Очищаем ответ от возможных обёрток
        let cleaned = cleanJSONResponse(text)
        
        // Парсим через JSONSerialization (более гибкий, чем Codable)
        guard let jsonData = cleaned.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw VisionError.parsingFailed("Invalid JSON: \(cleaned.prefix(100))")
        }
        
        // Определяем категорию
        guard let categoryStr = dict["category"] as? String,
              let category = RecognitionCategory(rawValue: categoryStr) else {
            // Если категории нет, пробуем как старый формат (обратная совместимость)
            return try parseLegacyFormat(dict: dict)
        }
        
        // MARK: Парсинг по категории
        
        switch category {
        case .item:
            return parseItemCategory(dict: dict)
        case .bulky, .otherObjects, .unclear:
            return parseRejectionCategory(category: category, dict: dict)
        }
    }
    
    // MARK: - Парсинг категории item
    
    /// Извлекаем детальное описание предмета из JSON.
    private func parseItemCategory(dict: [String: Any]) -> ItemRecognition {
        let material = (dict["material"] as? String)?.lowercased() ?? "N/A"
        let itemType = (dict["itemType"] as? String)?.lowercased() ?? ""
        
        // contentsUse может быть массивом строк или строкой
        var contents: [String] = []
        if let arr = dict["contentsUse"] as? [String] {
            contents = arr.map { $0.lowercased() }
        } else if let str = dict["contentsUse"] as? String {
            contents = str.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        }
        if contents.isEmpty { contents = ["N/A"] }
        
        return ItemRecognition(
            category: .item,
            material: material,
            itemType: itemType,
            contentsUse: contents
        )
    }
    
    // MARK: - Парсинг категорий отказа (bulky, otherObjects, unclear)
    
    /// Формируем результат с сообщением для пользователя.
    private func parseRejectionCategory(
        category: RecognitionCategory,
        dict: [String: Any]
    ) -> ItemRecognition {
        // Берём сообщение из ответа или используем дефолтное
        let message = dict["message"] as? String ?? defaultMessage(for: category)
        
        return ItemRecognition(
            category: category,
            rejectionMessage: message,
            material: "N/A",
            itemType: "N/A",
            contentsUse: ["N/A"]
        )
    }
    
    // MARK: - Дефолтные сообщения для категорий отказа
    
    /// Сообщения на случай, если модель не вернула своё.
    private func defaultMessage(for category: RecognitionCategory) -> String {
        switch category {
        case .bulky:
            return "This appears to be a large household item. Our app focuses on everyday packaging and small items. For large item disposal options, contact your local waste management service."
        case .otherObjects:
            return "This image doesn't appear to contain a recyclable or disposable item. Please photograph packaging, containers, or small household items."
        case .unclear:
            return "We couldn't clearly identify an item in this photo. Please try taking a clearer photo with good lighting."
        case .item:
            return ""
        }
    }
    
    // MARK: - Обратная совместимость со старым форматом
    
    /// Если в ответе нет поля category, парсим как старый формат (только item).
    private func parseLegacyFormat(dict: [String: Any]) throws -> ItemRecognition {
        let material = (dict["material"] as? String)?.lowercased() ?? ""
        let itemType = (dict["itemType"] as? String)?.lowercased() ?? ""
        
        guard !itemType.isEmpty else {
            throw VisionError.parsingFailed("No category or itemType found")
        }
        
        var contents: [String] = []
        if let arr = dict["contentsUse"] as? [String] {
            contents = arr.map { $0.lowercased() }
        } else if let arr = dict["searchKeywords"] as? [String] {
            // Совместимость со старым именем поля
            contents = arr.map { $0.lowercased() }
        }
        if contents.isEmpty { contents = ["N/A"] }
        
        return ItemRecognition(
            category: .item,
            material: material.isEmpty ? "N/A" : material,
            itemType: itemType,
            contentsUse: contents
        )
    }
    
    // MARK: - Очистка JSON-ответа
    
    /// Убираем markdown-обёртки и лишние символы из ответа модели.
    private func cleanJSONResponse(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Убираем markdown code fences: ```json ... ``` или ``` ... ```
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3))
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Убираем кавычки, если весь ответ обёрнут
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") {
            cleaned = String(cleaned.dropFirst().dropLast())
        }
        
        return cleaned
    }
}
