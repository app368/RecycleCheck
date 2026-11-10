import Foundation

// MARK: - Ответы города (уточнения из писем команды сайта)
// Ответ команды сайта на вопрос о предмете — точнее любого пункта сайта:
// в нём есть условия («всё металлическое — можно, есть пластик — мусор»).
// Ответ превращается в пункты того же вида, что пункты базы сайта, и
// хранится отдельно от неё (city_answers.json): Refresh его не стирает.
// При проверке ответы города главнее пунктов сайта (VerdictService).

nonisolated struct CityAnswerRule: Codable, Identifiable, Equatable {
    let id: UUID

    /// Что разрешено или запрещено — как пункт списка
    /// («all-metal kitchen utensils»); пользователь может поправить
    var itemText: String

    /// Можно или нельзя в бак переработки
    let verdict: RuleVerdict

    /// Дословная цитата из письма, на которой основан пункт
    let quote: String

    /// Когда ответ сохранён в приложении
    let receivedAt: Date

    /// Проверка, по которой был задан вопрос; nil — если её уже нет
    let historyEntryID: UUID?

    init(id: UUID = UUID(), itemText: String, verdict: RuleVerdict, quote: String,
         receivedAt: Date = Date(), historyEntryID: UUID?) {
        self.id = id
        self.itemText = itemText
        self.verdict = verdict
        self.quote = quote
        self.receivedAt = receivedAt
        self.historyEntryID = historyEntryID
    }

    /// Подпись источника для цитаты на экране результата
    var sourceLabel: String {
        "Reply from the city, " + receivedAt.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// Тот же пункт в виде пункта базы — для общего решения по найденным пунктам.
    /// Ссылки на страницу нет: источник — письмо
    var asRuleEntry: RuleEntry {
        RuleEntry(
            id: id,
            material: nil,
            itemText: itemText,
            verdict: verdict,
            origin: RuleOrigin(quote: quote, pageURL: "", section: sourceLabel, sourceForm: .prose)
        )
    }
}
