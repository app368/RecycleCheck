import Foundation

// MARK: - Конвейер сборки базы правил (П2.4)
// «Refresh source pages» одним конвейером: дискавери страниц со списками
// (LinkDiscoveryService) → загрузка каждой страницы (WebScrapingService)
// → AI-извлечение пунктов (RuleExtractionService) → слияние в SiteRules
// → сохранение (StorageService).
// Сбой одной страницы не роняет конвейер: страница пропускается,
// база собирается из остальных. Кэш целевых URL сохраняется как и раньше —
// старый поиск (СП3/СП4.1) работает на нём до перехода на вердикт по базе.

final class SiteRulesBuilder {

    static let shared = SiteRulesBuilder()

    private init() {}

    // MARK: - Ошибки конвейера

    enum BuildError: LocalizedError {
        case noPagesProcessed

        var errorDescription: String? {
            switch self {
            case .noPagesProcessed:
                return "Could not process any of the website pages"
            }
        }
    }

    // MARK: - Сборка базы правил

    /// Полный цикл сборки: дискавери → извлечение → слияние → сохранение.
    /// - Parameter baseURLString: базовый URL сайта переработки
    /// - Returns: собранная база правил (уже сохранена в StorageService)
    func buildRules(baseURLString: String) async throws -> SiteRules {
        let baseURL = URLNormalizer.normalize(baseURLString)

        // MARK: Дискавери страниц со списками правил (П2.1)

        let targetURLs = try await LinkDiscoveryService.shared
            .discoverTargetPages(baseURLString: baseURL)

        // Кэш целевых URL — промежуточный продукт конвейера,
        // на нём продолжает работать старый поиск СП3/СП4.1
        StorageService.shared.saveTargetURLs(targetURLs, forBaseURL: baseURL)

        // MARK: Извлечение пунктов по страницам (П2.2 + П2.3)

        var entries: [RuleEntry] = []
        var processedPages: [String] = []

        for pageURL in targetURLs {
            // Недоступная страница или сбой извлечения — пропускаем страницу,
            // конвейер продолжает работу на остальных
            guard let html = try? await WebScrapingService.shared
                .fetchPage(urlString: pageURL) else {
                continue
            }
            guard let pageEntries = try? await RuleExtractionService.shared
                .extractRules(fromHTML: html, pageURL: pageURL) else {
                continue
            }

            processedPages.append(pageURL)
            entries.append(contentsOf: pageEntries)
        }

        // Ни одной обработанной страницы — сборка не удалась
        guard !processedPages.isEmpty else {
            throw BuildError.noPagesProcessed
        }

        // MARK: Слияние и сохранение

        let rules = SiteRules(
            baseURL: baseURL,
            builtAt: Date(),
            processedPages: processedPages,
            entries: entries
        )
        StorageService.shared.saveSiteRules(rules)

        return rules
    }
}
