import Foundation

// MARK: - База правил сайта (списочная архитектура, П1)
// Модели структурированной базы правил, извлечённой с сайта переработки
// конвейером «Refresh source pages»: дискавери страниц со списками
// + AI-извлечение структуры (П2).
// Вердикт по предмету строится матчингом против этой базы (П3),
// без чтения страниц сайта в момент проверки.

// MARK: - Тип пункта правила

/// Разрешён или запрещён предмет в баке переработки.
/// Пример: «All glass bottles and jars» в секции Allowed → .allowed;
/// «NO window glass or mirrors» → .notAllowed.
/// База охватывает только переработку (recycling); компост и мусор —
/// отдельная задача, в базу не попадают
nonisolated enum RuleVerdict: String, Codable, Equatable {
    case allowed
    case notAllowed = "not_allowed"
}

// MARK: - Форма источника

/// В какой форме пункт был представлен на странице.
/// Нужна для оценки надёжности извлечения и отладки экстрактора
nonisolated enum RuleSourceForm: String, Codable, Equatable {
    /// Элемент списка (li)
    case list
    /// Предложение из прозы
    case prose
    /// Alt-текст или подпись картинки
    case imageCaption = "image_caption"
}

// MARK: - Происхождение пункта

/// Происхождение пункта — дословная цитата и её координаты на сайте.
/// Подтверждение вердикта для пользователя строится из этих полей
/// (пункт + секция), ссылка Source ведёт на pageURL
nonisolated struct RuleOrigin: Codable, Equatable {
    /// Дословная цитата с сайта, из которой извлечён пункт
    let quote: String

    /// URL страницы, где найдена цитата
    let pageURL: String

    /// Секция/заголовок, под которым находилась цитата
    /// (например «Allowed glass items»); пустая строка, если секции нет
    let section: String

    /// Форма представления на странице
    let sourceForm: RuleSourceForm
}

// MARK: - Пункт базы правил

/// Один пункт базы правил — нормативное утверждение сайта о том,
/// что разрешено или запрещено класть в конкретный поток.
/// Экстрактор консервативен: пункт создаётся только если из одной цитаты
/// можно ответить «класть ли X в бак?»; пояснения-«почему» пунктами не становятся
nonisolated struct RuleEntry: Codable, Identifiable, Equatable {
    let id: UUID

    /// Материал, к которому относится пункт (glass, plastic, paper...);
    /// nil — материал в цитате не выражен
    let material: String?

    /// Нормативный текст пункта («glass bottles and jars»)
    let itemText: String

    /// Разрешён или запрещён в баке переработки
    let verdict: RuleVerdict

    /// Условия применимости пункта (например «only if clean and dry»);
    /// пустой массив — без условий
    let conditions: [String]

    /// Инструкции по подготовке (например «rinse and flatten»);
    /// пустой массив — подготовка не упомянута
    let preparation: [String]

    /// Дословная цитата-происхождение
    let origin: RuleOrigin

    init(
        id: UUID = UUID(),
        material: String?,
        itemText: String,
        verdict: RuleVerdict,
        conditions: [String] = [],
        preparation: [String] = [],
        origin: RuleOrigin
    ) {
        self.id = id
        self.material = material
        self.itemText = itemText
        self.verdict = verdict
        self.conditions = conditions
        self.preparation = preparation
        self.origin = origin
    }
}

// MARK: - База правил сайта

/// База правил сайта — результат конвейера «Refresh source pages».
/// Хранится локально (StorageService), пересобирается кнопкой Refresh
nonisolated struct SiteRules: Codable, Equatable {
    /// Нормализованный базовый URL сайта, для которого собрана база
    let baseURL: String

    /// Дата сборки базы
    let builtAt: Date

    /// Страницы, обработанные экстрактором (для статуса в Settings и отладки)
    let processedPages: [String]

    /// Все пункты правил со всех страниц
    var entries: [RuleEntry]

    /// Строка состояния для Settings: «6 pages · 42 rules»
    var summary: String {
        "\(processedPages.count) pages · \(entries.count) rules"
    }

    /// Пустая ли база (страницы обработаны, но пунктов не извлечено)
    var isEmpty: Bool {
        entries.isEmpty
    }
}
