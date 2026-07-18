import Foundation

// MARK: - Человекочитаемые сообщения об ошибках
// Единая точка перевода технических ошибок (сетевые сбои, коды статуса API,
// сырой JSON) в понятный пользователю текст. Технические детали остаются
// только в консоли (print), на экран не попадают.

/// Возвращает готовую пару (заголовок, сообщение) для алерта — без
/// парсинга строк на стороне экрана. message пустой, если для ошибки
/// достаточно одной короткой фразы в заголовке
func friendlyError(from error: Error) -> (title: String, message: String) {
    print("Original error: \(error)")

    // Сбой сети (нет интернета, таймаут и т.п.)
    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return ("No internet connection", "Please check your connection and try again.")
        case .timedOut:
            return ("The request timed out", "Please try again.")
        case .cannotFindHost, .cannotConnectToHost, .badURL, .unsupportedURL:
            return ("Website not found", "Please check the address.")
        default:
            return ("A network error occurred", "Please try again.")
        }
    }

    // Сайт не открылся (плохой адрес, сайт лёг, неожиданный формат ответа)
    if error is WebScrapingService.ScrapingError {
        return ("Could not open the website", "Please check the address.")
    }

    let text = "\(error)"

    // Перегрузка AI-сервиса (Anthropic API возвращает 429/529 при перегрузке)
    if text.contains("Status 529") || text.contains("Status 429")
        || text.contains("overloaded_error") || text.contains("rate_limit") {
        return ("The AI service is busy right now", "Please try again in a minute.")
    }

    // Уже человекочитаемое сообщение (наши LocalizedError-типы) —
    // используем его, если оно не похоже на сырой технический текст
    // (JSON, коды статуса, длинные системные строки)
    let localized = error.localizedDescription
    if !localized.isEmpty,
       !localized.contains("{"),
       !localized.contains("Status "),
       localized.count < 150 {
        return (localized, "")
    }

    return ("Something went wrong", "Please try again.")
}
