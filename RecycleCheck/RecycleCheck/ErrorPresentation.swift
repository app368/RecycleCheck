import Foundation

// MARK: - Человекочитаемые сообщения об ошибках
// Единая точка перевода технических ошибок (сетевые сбои, коды статуса API,
// сырой JSON) в понятный пользователю текст. Технические детали остаются
// только в консоли (print), на экран не попадают.

/// Возвращает понятный пользователю текст для любой ошибки.
/// Уже человекочитаемые сообщения (LocalizedError с осмысленным
/// errorDescription) пропускаются как есть; технические — заменяются.
func friendlyErrorMessage(from error: Error) -> String {
    print("Original error: \(error)")

    // Сбой сети (нет интернета, таймаут и т.п.)
    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return "No internet connection. Please check your connection and try again."
        case .timedOut:
            return "The request timed out. Please try again."
        default:
            return "A network error occurred. Please try again."
        }
    }

    let text = "\(error)"

    // Перегрузка AI-сервиса (Anthropic API возвращает 429/529 при перегрузке)
    if text.contains("Status 529") || text.contains("Status 429")
        || text.contains("overloaded_error") || text.contains("rate_limit") {
        return "The AI service is busy right now. Please try again in a minute."
    }

    // Уже человекочитаемое сообщение (наши LocalizedError-типы) —
    // используем его, если оно не похоже на сырой технический текст
    // (JSON, коды статуса, длинные системные строки)
    let localized = error.localizedDescription
    if !localized.isEmpty,
       !localized.contains("{"),
       !localized.contains("Status "),
       localized.count < 150 {
        return localized
    }

    return "Something went wrong. Please try again."
}
