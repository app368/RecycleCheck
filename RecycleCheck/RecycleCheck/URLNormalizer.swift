import Foundation

// MARK: - Нормализация URL (СП3.1)
// Единые правила приведения URL к каноничному виду.
// Устраняет дубли целевых страниц в кэше (".../recycling?" против ".../recycling"),
// из-за которых одна и та же страница попадала в обработку дважды.

// nonisolated — чистая функция без состояния, используется и из
// MainActor-кода (SettingsView), и из фоновых сервисов конвейера Update
nonisolated enum URLNormalizer {

    /// Приводит URL к каноничному виду:
    /// — обрезает пробелы по краям;
    /// — убирает query (?...) и fragment (#...) целиком: для контентных страниц
    ///   сайтов переработки параметры не значимы (utm-хвосты и т.п.),
    ///   сборщик ссылок и раньше их отбрасывал;
    /// — убирает хвостовые «?» и «/» (кроме корня сайта);
    /// — схему и хост приводит к нижнему регистру (путь не трогаем —
    ///   он регистрозависим).
    /// Если строка не разбирается как URL — возвращает её после трима,
    /// валидацию оставляем вызывающему коду.
    static func normalize(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard var components = URLComponents(string: trimmed) else {
            return trimmed
        }

        // Убираем параметры и фрагмент
        components.query = nil
        components.fragment = nil

        // Схема и хост — в нижний регистр
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()

        // Хвостовой слэш пути (кроме корня "/")
        if components.path.count > 1, components.path.hasSuffix("/") {
            components.path = String(components.path.dropLast())
        }

        guard var normalized = components.string else {
            return trimmed
        }

        // Подстраховка: одиночный «?» без параметров
        if normalized.hasSuffix("?") {
            normalized = String(normalized.dropLast())
        }

        return normalized
    }
}
