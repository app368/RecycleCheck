import Foundation

// MARK: - Сервис поиска на сайте (СП3)
// Ищет предмет на сайте переработки через web scraping HTML-страниц.
// Получает структурированное описание предмета (от СП2),
// загружает страницы сайта и ищет совпадения с учётом весов.
// material и itemType имеют высший приоритет при поиске,
// contentsUse — дополнительный вес.
// Возвращает SearchResult для отображения (СП4).

final class WebScrapingService {
    
    static let shared = WebScrapingService()
    
    private init() {}
    
    // MARK: - Ошибки сервиса
    
    enum ScrapingError: LocalizedError {
        case invalidURL
        case networkError(Error)
        case parsingFailed
        case noSearchText
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid website URL"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .parsingFailed:
                return "Failed to read the website content"
            case .noSearchText:
                return "No description available for search"
            }
        }
    }
    
    // MARK: - Веса для поиска
    
    /// Вес совпадения по материалу (высший приоритет)
    private let materialWeight = 3
    
    /// Вес совпадения по типу предмета (высший приоритет)
    private let itemTypeWeight = 3
    
    /// Вес совпадения по содержимому / назначению (Contents/Intended Use)
    private let contentsWeight = 1
    
    /// Минимальный порог релевантности для признания совпадения
    private let relevanceThreshold = 3
    
    // MARK: - Поиск предмета на сайте (СП3.2 — многостраничный)
    
    /// Ищет предмет по целевым страницам сайта.
    /// Сначала ищет на главной и каталожных страницах,
    /// затем по отдельным страницам предметов.
    /// Останавливается при первом найденном результате.
    /// - Parameter item: предмет с описанием (от AI или от пользователя)
    /// - Returns: результат поиска со статусом и доказательством
    func searchItem(_ item: RecycleItem) async throws -> SearchResult {
        
        // Берём текст для поиска
        guard let searchText = item.searchText, !searchText.isEmpty else {
            throw ScrapingError.noSearchText
        }
        
        let baseURL = AppConfig.recyclingWebsiteURL
        
        // MARK: Получаем список целевых страниц из кэша или используем только главную
        
        let targetURLs = StorageService.shared.loadTargetURLs(forBaseURL: baseURL) ?? [baseURL]
        
        // MARK: Обходим страницы последовательно, ищем совпадения
        
        for pageURL in targetURLs {
            // Загружаем HTML страницы
            guard let html = try? await fetchPage(urlString: pageURL) else {
                continue // Если страница недоступна — пропускаем
            }
            
            // Ищем совпадения
            let result: SearchResult
            
            if let recognition = item.recognition, recognition.isValid {
                result = parseHTMLWeighted(html: html, recognition: recognition, sourceURL: pageURL)
            } else {
                result = parseHTML(html: html, searchText: searchText, sourceURL: pageURL)
            }
            
            // Если нашли — возвращаем результат, не обходим остальные страницы
            if result.status != .notFound {
                return result
            }
        }
        
        // Не найдено ни на одной странице
        return SearchResult(status: .notFound)
    }
    
    // MARK: - Загрузка HTML-страницы
    
    /// Загружает HTML-контент по указанному URL.
    func fetchPage(urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw ScrapingError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        // Представляемся обычным браузером для корректной отдачи контента
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ScrapingError.parsingFailed
        }
        
        // Определяем кодировку из ответа, по умолчанию UTF-8
        let encoding: String.Encoding
        if let encodingName = httpResponse.textEncodingName {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(encodingName as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
            } else {
                encoding = .utf8
            }
        } else {
            encoding = .utf8
        }
        
        guard let html = String(data: data, encoding: encoding) else {
            throw ScrapingError.parsingFailed
        }
        
        return html
    }
    
    // MARK: - Взвешенный поиск по структурированному описанию
    
    /// Ищет предмет в HTML с учётом весов: material и itemType имеют высший приоритет.
    /// - Parameters:
    ///   - html: HTML-контент страницы
    ///   - recognition: структурированное описание предмета
    /// - Returns: результат поиска
    private func parseHTMLWeighted(html: String, recognition: ItemRecognition, sourceURL: String = "") -> SearchResult {
        
        // Извлекаем текстовый контент, убирая HTML-теги
        let plainText = stripHTMLTags(html)
        let textLower = plainText.lowercased()
        let sentences = splitIntoSentences(textLower)
        let originalSentences = splitIntoSentences(plainText)
        
        // Подготавливаем слова для поиска с весами
        let materialWords = recognition.material.lowercased()
            .split(separator: " ").map(String.init)
        let itemTypeWords = recognition.itemType.lowercased()
            .split(separator: " ").map(String.init)
        let contentsWords = recognition.contentsUse
            .map { $0.lowercased() }
            .filter { $0.count > 2 }
        
        // Ищем лучшее совпадение по взвешенному счёту
        var bestMatch: (sentence: String, score: Int, originalSentence: String)?
        
        for (index, sentence) in sentences.enumerated() where index < originalSentences.count {
            var score = 0
            
            // Совпадения по материалу (высший вес)
            for word in materialWords where sentence.contains(word) {
                score += materialWeight
            }
            
            // Совпадения по типу предмета (высший вес)
            for word in itemTypeWords where sentence.contains(word) {
                score += itemTypeWeight
            }
            
            // Совпадения по содержимому / назначению
            for word in contentsWords where sentence.contains(word) {
                score += contentsWeight
            }
            
            if score > 0 {
                if bestMatch == nil || score > bestMatch!.score {
                    bestMatch = (sentence, score, originalSentences[index])
                }
            }
        }
        
        // MARK: Формируем результат
        
        guard let match = bestMatch, match.score >= relevanceThreshold else {
            // Предмет не найден или недостаточно релевантный результат
            return SearchResult(status: .notFound)
        }
        
        // Определяем статус: ищем маркеры пригодности / непригодности
        let status = determineStatus(text: match.sentence)
        
        // Извлекаем фрагмент текста как доказательство
        let evidence = extractEvidence(
            fullText: plainText,
            matchedSentence: match.originalSentence
        )
        
        return SearchResult(
            status: status,
            evidence: evidence,
            sourceURL: sourceURL
        )
    }
    
    // MARK: - Старый поиск по тексту (обратная совместимость)
    
    /// Ищет текстовое описание предмета в HTML-контенте страницы.
    private func parseHTML(html: String, searchText: String, sourceURL: String = "") -> SearchResult {
        
        let plainText = stripHTMLTags(html)
        
        let keywords = searchText
            .lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 2 }
        
        guard !keywords.isEmpty else {
            return SearchResult(status: .notFound)
        }
        
        let textLower = plainText.lowercased()
        let sentences = splitIntoSentences(textLower)
        
        var bestMatch: (sentence: String, matchCount: Int, originalSentence: String)?
        let originalSentences = splitIntoSentences(plainText)
        
        for (index, sentence) in sentences.enumerated() where index < originalSentences.count {
            let matchCount = keywords.filter { sentence.contains($0) }.count
            if matchCount > 0 {
                if bestMatch == nil || matchCount > bestMatch!.matchCount {
                    bestMatch = (sentence, matchCount, originalSentences[index])
                }
            }
        }
        
        guard let match = bestMatch else {
            return SearchResult(status: .notFound)
        }
        
        let status = determineStatus(text: match.sentence)
        
        let evidence = extractEvidence(
            fullText: plainText,
            matchedSentence: match.originalSentence
        )
        
        return SearchResult(
            status: status,
            evidence: evidence,
            sourceURL: sourceURL
        )
    }
    
    // MARK: - Определение статуса пригодности
    
    /// Анализирует текст на наличие маркеров пригодности / непригодности.
    private func determineStatus(text: String) -> RecycleStatus {
        let lowerText = text.lowercased()
        
        // Маркеры непригодности
        let notRecyclableMarkers = [
            "not recyclable", "cannot be recycled", "non-recyclable",
            "do not recycle", "not accepted", "trash", "landfill",
            "cannot recycle", "don't recycle", "not suitable"
        ]
        
        // Маркеры пригодности
        let recyclableMarkers = [
            "recyclable", "can be recycled", "accepted",
            "recycle bin", "recycling", "compostable",
            "can recycle", "is accepted"
        ]
        
        // Сначала проверяем непригодность (более строгие маркеры)
        for marker in notRecyclableMarkers {
            if lowerText.contains(marker) {
                return .notRecyclable
            }
        }
        
        // Затем пригодность
        for marker in recyclableMarkers {
            if lowerText.contains(marker) {
                return .recyclable
            }
        }
        
        return .recyclable
    }
    
    // MARK: - Извлечение фрагмента-доказательства
    
    /// Вырезает фрагмент текста вокруг найденного совпадения (до 300 символов).
    private func extractEvidence(fullText: String, matchedSentence: String) -> String {
        guard let range = fullText.range(of: matchedSentence) else {
            return String(matchedSentence.prefix(300))
        }
        
        let startIndex = range.lowerBound
        let distanceFromStart = fullText.distance(from: fullText.startIndex, to: startIndex)
        
        let contextStart = fullText.index(
            fullText.startIndex,
            offsetBy: max(0, distanceFromStart - 50)
        )
        let contextEnd = fullText.index(
            startIndex,
            offsetBy: min(300, fullText.distance(from: startIndex, to: fullText.endIndex))
        )
        
        var evidence = String(fullText[contextStart..<contextEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if contextStart > fullText.startIndex { evidence = "..." + evidence }
        if contextEnd < fullText.endIndex { evidence = evidence + "..." }
        
        return evidence
    }
    
    // MARK: - Вспомогательные методы
    
    /// Удаляет HTML-теги и декодирует HTML-сущности.
    func stripHTMLTags(_ html: String) -> String {
        var text = html
        let patterns = [
            "<script[^>]*>[\\s\\S]*?</script>",
            "<style[^>]*>[\\s\\S]*?</style>",
            "<[^>]+>"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                text = regex.stringByReplacingMatches(
                    in: text,
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: " "
                )
            }
        }
        
        text = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        
        if let regex = try? NSRegularExpression(pattern: "\\s+") {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: " "
            )
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Разбивает текст на предложения.
    func splitIntoSentences(_ text: String) -> [String] {
        let delimiters = CharacterSet(charactersIn: ".!?\n")
        return text
            .components(separatedBy: delimiters)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
