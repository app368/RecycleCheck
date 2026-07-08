import Foundation

// MARK: - Сервис обнаружения целевых страниц (СП3.1)
// Загружает главную страницу сайта переработки,
// извлекает все внутренние ссылки, фильтрует нерелевантные,
// отправляет оставшиеся в Claude API для умной классификации.
// Возвращает список URL страниц, на которых можно искать информацию о предметах.

final class LinkDiscoveryService {
    
    static let shared = LinkDiscoveryService()
    
    private init() {}
    
    // MARK: - Ошибки сервиса
    
    enum DiscoveryError: LocalizedError {
        case invalidBaseURL
        case noLinksFound
        case aiFilteringFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                return "Invalid website URL"
            case .noLinksFound:
                return "No relevant pages found on the website"
            case .aiFilteringFailed(let detail):
                return "AI filtering failed: \(detail)"
            }
        }
    }
    
    // MARK: - Стоп-слова для жёсткой фильтрации путей
    
    /// Сегменты пути, которые указывают на служебные страницы
    private let stopPathSegments = [
        "about", "contact", "privacy", "terms", "login", "signup",
        "register", "account", "cart", "checkout", "donate", "sponsor",
        "partner", "press", "media", "career", "job", "faq", "help",
        "support", "game", "play", "newsletter", "subscribe", "search",
        "feedback", "advisory", "council", "events", "calendar",
        "construction", "neighborhoods", "services", "jobs",
        "charter", "code", "policies", "bureaus", "offices",
        "parks", "projects", "news"
    ]
    
    // MARK: - Обнаружение целевых страниц
    
    /// Основной метод: загружает сайт, собирает ссылки, фильтрует, возвращает целевые URL.
    /// - Parameter baseURLString: URL главной страницы сайта
    /// - Returns: массив URL целевых страниц для поиска (нормализованных, без дублей)
    func discoverTargetPages(baseURLString rawBaseURLString: String) async throws -> [String] {

        // Приводим базовый URL к каноничному виду — иначе грязный URL
        // из Settings (хвостовой «?», utm-параметры) попадёт в список
        // целевых страниц и продублирует страницу, найденную по ссылкам
        let baseURLString = URLNormalizer.normalize(rawBaseURLString)

        // Проверяем базовый URL
        guard let baseURL = URL(string: baseURLString),
              let host = baseURL.host else {
            throw DiscoveryError.invalidBaseURL
        }
        
        // MARK: Загружаем HTML главной страницы
        
        let html = try await WebScrapingService.shared.fetchPage(urlString: baseURLString)
        
        // MARK: Извлекаем все ссылки из HTML
        
        let allLinks = extractLinks(from: html, baseURL: baseURL, host: host)
        
        guard !allLinks.isEmpty else {
            // Если ссылок нет — возвращаем только главную страницу
            return [baseURLString]
        }
        
        // MARK: Жёсткая фильтрация (Уровень 1)
        
        let filteredLinks = hardFilter(links: allLinks, host: host, baseURL: baseURL)
        
        guard !filteredLinks.isEmpty else {
            return [baseURLString]
        }
        
        // MARK: AI-фильтрация (Уровень 2)
        
        let targetLinks = try await aiFilter(links: filteredLinks, baseURLString: baseURLString)
        
        // Всегда включаем главную страницу в начало списка.
        // Дедупликация с сохранением порядка: все URL уже нормализованы,
        // поэтому копии одной страницы схлопываются
        var result: [String] = []
        var seen = Set<String>()
        for link in [baseURLString] + targetLinks where seen.insert(link).inserted {
            result.append(link)
        }

        return result
    }
    
    // MARK: - Извлечение ссылок из HTML
    
    /// Парсит HTML и извлекает все URL из тегов <a href="...">.
    private func extractLinks(from html: String, baseURL: URL, host: String) -> [String] {
        var links: Set<String> = []
        
        // Regex для поиска href в тегах <a>
        let pattern = "<a[^>]+href\\s*=\\s*[\"']([^\"'#]+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }
        
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        
        for match in matches {
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            var href = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Пропускаем спецсхемы
            if href.hasPrefix("mailto:") || href.hasPrefix("tel:") || href.hasPrefix("javascript:") {
                continue
            }
            
            // Преобразуем относительные ссылки в абсолютные
            if href.hasPrefix("/") {
                guard let scheme = baseURL.scheme else { continue }
                href = "\(scheme)://\(host)\(href)"
            }
            
            // Пропускаем ссылки на другие домены
            guard let linkURL = URL(string: href),
                  let linkHost = linkURL.host,
                  linkHost == host else {
                continue
            }
            
            // Приводим к каноничному виду (query, fragment, слэши, регистр) —
            // единые правила с остальным кодом через URLNormalizer
            let cleanURL = URLNormalizer.normalize(href)
            if !cleanURL.isEmpty {
                links.insert(cleanURL)
            }
        }
        
        return Array(links)
    }
    
    // MARK: - Жёсткая фильтрация (Уровень 1)
    
    /// Отсекает очевидно нерелевантные ссылки по правилам.
    private func hardFilter(links: [String], host: String, baseURL: URL) -> [String] {
        return links.filter { link in
            guard let url = URL(string: link) else { return false }
            let path = url.path.lowercased()
            
            // Пропускаем ссылки на файлы
            let fileExtensions = [".pdf", ".jpg", ".jpeg", ".png", ".gif", ".zip", ".doc", ".xlsx"]
            for ext in fileExtensions {
                if path.hasSuffix(ext) { return false }
            }
            
            // Пропускаем корень (главную) — она уже включена
            if path == "/" || path.isEmpty { return false }
            
            // Пропускаем ссылки на переводы (обычно /es/, /ru/, /vi/, /zh-hans/ и т.д.)
            let translationPrefixes = ["/es/", "/ru/", "/vi/", "/zh-hans/", "/zh-hant/",
                                       "/ko/", "/ja/", "/fr/", "/de/", "/pt/", "/ar/"]
            for prefix in translationPrefixes {
                if path.hasPrefix(prefix) { return false }
            }
            
            // Пропускаем страницы со стоп-словами в пути
            let pathSegments = path.split(separator: "/").map { String($0).lowercased() }
            for segment in pathSegments {
                for stop in stopPathSegments {
                    if segment == stop { return false }
                }
            }
            
            return true
        }
    }
    
    // MARK: - AI-фильтрация (Уровень 2)
    
    /// Отправляет список ссылок в Claude API для умной классификации.
    /// AI определяет, какие страницы содержат информацию о предметах для переработки.
    private func aiFilter(links: [String], baseURLString: String) async throws -> [String] {
        
        // Формируем список путей для отправки в AI (без полных URL — экономим токены)
        let paths = links.compactMap { link -> String? in
            guard let url = URL(string: link) else { return nil }
            return url.path
        }
        
        let pathsList = paths.joined(separator: "\n")
        
        // MARK: Формируем запрос к Claude API
        
        // Дискавери нацелено на страницы со СПИСКАМИ правил переработки
        // (списочная архитектура): что разрешено/запрещено в баке переработки.
        // Компост и мусор — вне задачи, такие страницы не нужны
        let prompt = """
        You are analyzing a recycling website. Below is a list of URL paths from this website.

        Select ONLY the paths that likely contain LISTS OF RULES about what items are \
        allowed or not allowed in the household RECYCLING bin.

        INCLUDE paths that likely hold:
        - Lists of accepted / not accepted items for recycling
        - "What can I recycle" guides for residents
        - Rules for recyclable material categories (plastic, paper, glass, metal, etc.)
        - FAQ pages about what can or cannot be recycled

        EXCLUDE paths related to:
        - Compost, yard debris or garbage (this app only answers about recycling)
        - General information (about, contact, help)
        - News, blog posts, events
        - Services, schedules, rates, programs, policies
        - User accounts, settings
        - Games, apps, tools
        - Printable guides, PDF downloads
        - Educational content about the recycling process (how recycling works, benefits)
        - Business or commercial waste (the app serves households)

        Respond with ONLY a JSON array of the selected paths, no other text:
        ["<path1>", "<path2>"]

        If none of the paths are relevant, respond with: []

        PATHS:
        \(pathsList)
        """
        
        let requestBody: [String: Any] = [
            // claude-sonnet-4 отключён Anthropic 15.06.2026, заменён на sonnet-5
            "model": "claude-sonnet-5",
            // У sonnet-5 thinking включён по умолчанию — выключаем:
            // парсер ждёт JSON в первом блоке ответа
            "thinking": ["type": "disabled"],
            "max_tokens": 1000,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        
        guard let url = URL(string: AppConfig.visionAPIEndpoint) else {
            throw DiscoveryError.aiFilteringFailed("Invalid API endpoint")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.visionAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // MARK: Отправляем запрос и парсим ответ
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DiscoveryError.aiFilteringFailed("API request failed")
        }
        
        // Извлекаем текст ответа
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw DiscoveryError.aiFilteringFailed("Invalid API response")
        }
        
        // Очищаем ответ
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Парсим JSON-массив путей
        guard let jsonData = cleaned.data(using: .utf8),
              let selectedPaths = try? JSONSerialization.jsonObject(with: jsonData) as? [String] else {
            // Если парсинг не удался — возвращаем все ссылки после жёсткой фильтрации
            return links
        }
        
        // Преобразуем пути обратно в полные URL
        guard let baseURL = URL(string: baseURLString),
              let scheme = baseURL.scheme,
              let host = baseURL.host else {
            return links
        }
        
        let targetURLs = selectedPaths.compactMap { path -> String? in
            let fullURL = "\(scheme)://\(host)\(path)"
            // Проверяем, что этот URL был в исходном списке
            return links.contains(fullURL) ? fullURL : nil
        }
        
        return targetURLs.isEmpty ? links : targetURLs
    }
}
