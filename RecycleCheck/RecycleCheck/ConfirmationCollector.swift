import Foundation

// MARK: - Сервис сбора упоминаний предмета (СП4.1 «Подтверждение вердикта», шаг 1)
// Проходит по уже известным целевым URL сайта переработки,
// загружает страницы и собирает все абзацы, в которых упоминается предмет.
// Каждое упоминание (Mention) — это один абзац + URL источника + взвешенный скоринг.
// Лимиты: максимум 15 упоминаний, максимум 12 000 символов суммарно.
// При превышении лимита — отбирает топ по скорингу.
//
// Сервис НЕ вызывает Claude AI и НЕ меняет UI — это следующие шаги.
// Используется существующий WebScrapingService только для загрузки HTML.

final class ConfirmationCollector {
    
    static let shared = ConfirmationCollector()
    
    private init() {}
    
    // MARK: - Лимиты на сбор упоминаний
    
    /// Максимальное число упоминаний для отправки в Claude AI
    private static let maxMentions = 15
    
    /// Максимальный суммарный объём текста (символов)
    private static let maxTotalCharacters = 12_000
    
    // MARK: - Веса скоринга (согласованы с СП3 «Поиск на сайте»)
    
    /// Вес совпадения по материалу (высший приоритет)
    private static let materialWeight = 3
    
    /// Вес совпадения по типу предмета (высший приоритет)
    private static let itemTypeWeight = 3
    
    /// Вес совпадения по содержимому / назначению
    private static let contentsWeight = 1
    
    /// Минимальная длина ключевого слова, которое имеет смысл искать
    /// (отбрасываем короткие предлоги и шум)
    private static let minKeywordLength = 3
    
    /// Минимальная длина абзаца, имеющего смысл (отбрасываем
    /// короткие пункты меню, копирайты, разделители)
    private static let minParagraphLength = 30
    
    // MARK: - Ошибки сервиса
    
    enum CollectorError: LocalizedError {
        case noTargetURLs
        case noKeywords
        
        var errorDescription: String? {
            switch self {
            case .noTargetURLs:
                return "No target pages available for confirmation search"
            case .noKeywords:
                return "No keywords available to search for mentions"
            }
        }
    }
    
    // MARK: - Структура упоминания
    
    /// Сырой кусок текста с сайта, в котором упоминается предмет.
    /// Минимальная единица материала, который потом будет передан в Claude AI.
    struct Mention {
        /// Текст абзаца
        let text: String
        
        /// URL страницы-источника
        let sourceURL: String
        
        /// Взвешенный скоринг (используется при отборе топа,
        /// когда лимиты превышены)
        let score: Int
    }
    
    // MARK: - Публичный API
    
    /// Собирает все упоминания предмета с указанных целевых страниц.
    /// - Parameters:
    ///   - recognition: структурированное описание предмета (от СП2)
    ///   - targetURLs: список URL целевых страниц сайта (из кэша СП3.1)
    /// - Returns: массив Mention, отобранных с учётом лимитов
    func collectMentions(
        for recognition: ItemRecognition,
        on targetURLs: [String]
    ) async throws -> [Mention] {
        
        // MARK: Базовые проверки входных данных
        
        guard !targetURLs.isEmpty else {
            throw CollectorError.noTargetURLs
        }
        
        // Подготавливаем ключевые слова с весами
        let keywords = prepareKeywords(from: recognition)
        
        guard !keywords.isEmpty else {
            throw CollectorError.noKeywords
        }
        
        // MARK: Сбор всех упоминаний со всех страниц
        
        var allMentions: [Mention] = []
        
        for pageURL in targetURLs {
            // Если страница недоступна — просто пропускаем,
            // не прерываем работу всего сервиса
            guard let html = try? await WebScrapingService.shared
                .fetchPage(urlString: pageURL) else {
                continue
            }
            
            // Извлекаем абзацы с сохранением структуры
            let paragraphs = extractParagraphs(from: html)
            
            // Ищем упоминания в каждом абзаце
            for paragraph in paragraphs {
                if let mention = makeMention(
                    fromParagraph: paragraph,
                    sourceURL: pageURL,
                    keywords: keywords
                ) {
                    allMentions.append(mention)
                }
            }
        }
        
        // MARK: Применяем лимиты
        
        return applyLimits(to: allMentions)
    }
    
    // MARK: - Подготовка ключевых слов с весами
    
    /// Внутренняя структура: ключевое слово + его вес для скоринга
    private struct WeightedKeyword {
        let word: String
        let weight: Int
    }
    
    /// Превращает ItemRecognition в плоский список ключевых слов с весами.
    /// Слова приводятся к нижнему регистру.
    /// Поля со значением "N/A" пропускаются.
    /// Слишком короткие слова (короче minKeywordLength) отбрасываются.
    private func prepareKeywords(from recognition: ItemRecognition) -> [WeightedKeyword] {
        var keywords: [WeightedKeyword] = []
        
        // Слова из материала (вес 3)
        if recognition.material.lowercased() != "n/a" {
            let words = recognition.material
                .lowercased()
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count >= Self.minKeywordLength }
            for word in words {
                keywords.append(WeightedKeyword(word: word, weight: Self.materialWeight))
            }
        }
        
        // Слова из типа предмета (вес 3)
        if recognition.itemType.lowercased() != "n/a" {
            let words = recognition.itemType
                .lowercased()
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count >= Self.minKeywordLength }
            for word in words {
                keywords.append(WeightedKeyword(word: word, weight: Self.itemTypeWeight))
            }
        }
        
        // Слова из содержимого / назначения (вес 1)
        for contentValue in recognition.contentsUse where contentValue.lowercased() != "n/a" {
            let words = contentValue
                .lowercased()
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count >= Self.minKeywordLength }
            for word in words {
                keywords.append(WeightedKeyword(word: word, weight: Self.contentsWeight))
            }
        }
        
        return keywords
    }
    
    // MARK: - Извлечение абзацев из HTML
    
    /// Извлекает абзацы из HTML с сохранением их структуры.
    /// Подход: блочные теги (</p>, </div>, <br>, </li>, заголовки) заменяются
    /// на маркер абзаца, затем удаляются остальные теги, затем текст
    /// разбивается по маркерам.
    /// Это отдельная логика, специфичная для СП4.1, поэтому она здесь,
    /// а не в WebScrapingService (там используется склейка в одну строку).
    private func extractParagraphs(from html: String) -> [String] {
        var text = html
        
        // Сначала вырезаем содержимое <script> и <style> вместе с тегами,
        // чтобы оно не попало в текст
        let scriptStylePatterns = [
            "<script[^>]*>[\\s\\S]*?</script>",
            "<style[^>]*>[\\s\\S]*?</style>"
        ]
        for pattern in scriptStylePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                text = regex.stringByReplacingMatches(
                    in: text,
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: " "
                )
            }
        }
        
        // Заменяем блочные теги на маркер абзаца "\n\n"
        // Это сохраняет структуру: то, что в HTML было разделено
        // блочными тегами, и в нашем тексте останется в разных абзацах
        let blockTagPatterns = [
            "</p\\s*>",
            "</div\\s*>",
            "<br\\s*/?\\s*>",
            "</li\\s*>",
            "</h[1-6]\\s*>",
            "</tr\\s*>",
            "</td\\s*>"
        ]
        for pattern in blockTagPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                text = regex.stringByReplacingMatches(
                    in: text,
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: "\n\n"
                )
            }
        }
        
        // Удаляем все остальные HTML-теги
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: .caseInsensitive) {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: " "
            )
        }
        
        // Декодируем основные HTML-сущности
        text = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        
        // Разбиваем текст на абзацы по маркерам
        let rawParagraphs = text.components(separatedBy: "\n\n")
        
        // Чистим каждый абзац: убираем многократные пробелы внутри,
        // обрезаем по краям, отбрасываем слишком короткие
        let cleanedParagraphs = rawParagraphs.compactMap { paragraph -> String? in
            var cleaned = paragraph
            // Сжимаем подряд идущие пробелы и переводы строк в один пробел
            if let regex = try? NSRegularExpression(pattern: "\\s+") {
                cleaned = regex.stringByReplacingMatches(
                    in: cleaned,
                    range: NSRange(cleaned.startIndex..., in: cleaned),
                    withTemplate: " "
                )
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Отбрасываем слишком короткие — это, скорее всего,
            // пункты меню, копирайты, разделители
            guard cleaned.count >= Self.minParagraphLength else {
                return nil
            }
            return cleaned
        }
        
        return cleanedParagraphs
    }
    
    // MARK: - Создание упоминания из абзаца
    
    /// Проверяет абзац на наличие ключевых слов и, если есть,
    /// формирует Mention со скорингом.
    /// Возвращает nil, если в абзаце не найдено ни одного ключевого слова.
    private func makeMention(
        fromParagraph paragraph: String,
        sourceURL: String,
        keywords: [WeightedKeyword]
    ) -> Mention? {
        let lowerParagraph = paragraph.lowercased()
        
        // Считаем суммарный скоринг абзаца:
        // каждое найденное ключевое слово добавляет свой вес
        var score = 0
        for keyword in keywords where lowerParagraph.contains(keyword.word) {
            score += keyword.weight
        }
        
        // Если ни одного совпадения — упоминания нет
        guard score > 0 else {
            return nil
        }
        
        return Mention(
            text: paragraph,
            sourceURL: sourceURL,
            score: score
        )
    }
    
    // MARK: - Применение лимитов
    
    /// Применяет лимиты к собранному списку упоминаний.
    /// Алгоритм:
    /// 1. Сортируем по убыванию скоринга (самые релевантные первыми).
    /// 2. Идём по списку и накапливаем, пока не упрёмся в один из лимитов
    ///    (число упоминаний или суммарный объём символов).
    /// 3. Возвращаем накопленный набор.
    /// Если лимиты не превышены — возвращаются все упоминания
    /// (но всё равно отсортированные по скорингу — для консистентности).
    private func applyLimits(to mentions: [Mention]) -> [Mention] {
        // Сортируем по убыванию скоринга
        let sorted = mentions.sorted { $0.score > $1.score }
        
        var result: [Mention] = []
        var totalCharacters = 0
        
        for mention in sorted {
            // Проверяем лимит по количеству
            if result.count >= Self.maxMentions {
                break
            }
            
            // Проверяем лимит по объёму
            let newTotal = totalCharacters + mention.text.count
            if newTotal > Self.maxTotalCharacters {
                // Если даже без этого упоминания объём уже большой —
                // не пытаемся впихнуть оставшиеся короткие, прерываемся
                break
            }
            
            result.append(mention)
            totalCharacters = newTotal
        }
        
        return result
    }
}
