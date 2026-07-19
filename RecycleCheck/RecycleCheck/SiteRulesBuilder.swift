import Foundation

// MARK: - Конвейер сборки базы правил (П2.4)
// «Update recycling data» работает только с URL, указанным в Settings:
// прямая загрузка страницы (WebScrapingService) → AI-извлечение пунктов
// (RuleExtractionService) → сохранение в SiteRules (StorageService).
// Связанные страницы не ищутся и не добавляются в базу правил.

final class SiteRulesBuilder {

    nonisolated static let shared = SiteRulesBuilder()

    private init() {}

    // MARK: - Сборка базы правил

    /// Полный цикл сборки: загрузка одной страницы → извлечение → сохранение.
    /// - Parameter baseURLString: URL страницы с правилами переработки
    /// - Returns: собранная база правил (уже сохранена в StorageService)
    nonisolated func buildRules(baseURLString: String) async throws -> SiteRules {
        let baseURL = URLNormalizer.normalize(baseURLString)

        let html = try await WebScrapingService.shared
            .fetchPage(urlString: baseURL)
        let entries = try await RuleExtractionService.shared
            .extractRules(fromHTML: html, pageURL: baseURL)

        // MARK: Сохранение

        let rules = SiteRules(
            baseURL: baseURL,
            builtAt: Date(),
            entries: entries
        )
        await StorageService.shared.saveSiteRules(rules)

        return rules
    }
}
