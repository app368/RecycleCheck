import Foundation

// MARK: - Загрузка HTML-страниц
// Утилита загрузки веб-страниц по URL. После перехода на списочную
// архитектуру от прежнего сервиса поиска осталась только загрузка HTML —
// её использует конвейер Update (SiteRulesBuilder).
// Поиск предмета теперь идёт по собранной базе списков (VerdictService),
// сами страницы при проверке не читаются.

final class WebScrapingService {

    // nonisolated — вся работа этого сервиса (сеть, парсинг) не должна
    // выполняться на главном потоке; проект по умолчанию изолирует всё
    // на MainActor (SWIFT_DEFAULT_ACTOR_ISOLATION), это явное исключение
    nonisolated static let shared = WebScrapingService()

    private init() {}

    // MARK: - Ошибки сервиса

    enum ScrapingError: LocalizedError {
        case invalidURL
        case parsingFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid website URL"
            case .parsingFailed:
                return "Website not found"
            }
        }
    }

    // MARK: - Загрузка HTML-страницы

    /// Загружает HTML-контент по указанному URL.
    nonisolated func fetchPage(urlString: String) async throws -> String {
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
}
