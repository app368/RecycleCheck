import Foundation
import SwiftUI

// MARK: - Модели данных RecycleCheck
// Описывают основные сущности приложения:
// предмет для проверки, результат распознавания, результат поиска, профиль пользователя.

// MARK: - Категория распознавания (грубый отсев, Этап 1)

/// Результат грубого отсева при распознавании изображения.
/// Определяет, применимо ли приложение к данному изображению.
enum RecognitionCategory: String, Codable, Equatable {
    /// Предмет, с которым приложение работает → переход к детальному распознаванию
    case item
    
    /// Крупногабаритный предмет (мебель, техника, матрас)
    case bulky
    
    /// Фото не содержит предмета для проверки (пейзаж, животное, человек, еда без упаковки)
    case otherObjects
    
    /// Изображение слишком размыто или AI не может определить предмет
    case unclear
}

// MARK: - Результат распознавания предмета (СП2)

/// Структурированное описание предмета, полученное от Claude Vision API.
/// Содержит результат двухэтапного распознавания:
/// — грубый отсев (category) определяет, применимо ли приложение
/// — детальное распознавание (material, itemType, contentsUse) заполняется только для category == .item
struct ItemRecognition: Codable, Equatable {
    
    /// Категория распознавания (грубый отсев)
    var category: RecognitionCategory
    
    /// Сообщение для пользователя при отказе (для bulky, otherObjects, unclear)
    var rejectionMessage: String?
    
    /// Основной материал предмета (plastic, paper, glass, metal, foam, fabric, wood, rubber)
    /// Может быть "N/A" для неперерабатываемых предметов
    var material: String
    
    /// Тип предмета (bottle, container, bag, cup, box, can, jar, lid, wrap, envelope)
    var itemType: String
    
    /// Содержимое / назначение предмета (beverage, food, dairy, cleaning, shipping)
    /// Может быть пустым или содержать "N/A"
    var contentsUse: [String]
    
    /// Полный текст для поиска — объединяет все поля, исключая N/A
    var fullSearchText: String {
        var parts: [String] = []
        if material.lowercased() != "n/a" { parts.append(material) }
        if itemType.lowercased() != "n/a" { parts.append(itemType) }
        let validContents = contentsUse.filter { $0.lowercased() != "n/a" }
        parts.append(contentsOf: validContents)
        return parts.joined(separator: " ")
    }
    
    /// Отображаемое название предмета с заглавной буквы
    var displayName: String {
        let materialPart = material.lowercased() == "n/a" ? "" : material
        let typePart = itemType.lowercased() == "n/a" ? "" : itemType
        let text = [materialPart, typePart]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !text.isEmpty else { return "Unknown item" }
        return text.prefix(1).uppercased() + text.dropFirst()
    }
    
    /// Отображаемое значение материала в UI
    var displayMaterial: String {
        material.lowercased() == "n/a" ? "Not applicable" : material
    }
    
    /// Отображаемое значение содержимого в UI
    var displayContentsUse: String {
        let valid = contentsUse.filter { $0.lowercased() != "n/a" }
        return valid.isEmpty ? "Not applicable" : valid.joined(separator: ", ")
    }
    
    /// Пустой результат распознавания
    static let empty = ItemRecognition(
        category: .item, material: "", itemType: "", contentsUse: []
    )
    
    /// Проверка, является ли предмет применимым для проверки
    var isApplicable: Bool {
        category == .item
    }
    
    /// Проверка, заполнены ли основные поля (хотя бы itemType)
    var isValid: Bool {
        !itemType.isEmpty && itemType.lowercased() != "n/a"
    }
}

// MARK: - Предмет для проверки (СП1)

/// Предмет, который пользователь хочет проверить на пригодность к переработке
struct RecycleItem: Identifiable, Codable {
    let id: UUID
    
    /// Описание предмета (опционально, вводит пользователь) — устаревшее поле,
    /// сохранено для обратной совместимости с историей
    var userDescription: String?
    
    /// Описание, полученное от AI Vision API (СП2) — устаревшее поле,
    /// сохранено для обратной совместимости с историей
    var aiDescription: String?
    
    /// Структурированное описание от AI Vision API (СП2, новая версия)
    var recognition: ItemRecognition?
    
    /// Имя файла фотографии в локальном хранилище
    var photoFileName: String?
    
    /// Дата создания запроса
    let createdAt: Date
    
    init(recognition: ItemRecognition? = nil, photoFileName: String? = nil) {
        self.id = UUID()
        self.recognition = recognition
        self.photoFileName = photoFileName
        self.createdAt = Date()
    }
    
    /// Обратная совместимость: старый инициализатор
    init(userDescription: String? = nil, photoFileName: String? = nil) {
        self.id = UUID()
        self.userDescription = userDescription
        self.photoFileName = photoFileName
        self.createdAt = Date()
    }
    
    /// Текст для поиска на сайте: приоритет — структурированное описание,
    /// затем AI-описание, затем пользовательское
    var searchText: String? {
        if let recognition = recognition, recognition.isValid {
            return recognition.fullSearchText
        }
        return aiDescription ?? userDescription
    }
    
    /// Отображаемое название предмета с заглавной первой буквой
    var displayName: String {
        if let recognition = recognition, recognition.isValid {
            return recognition.displayName
        }
        guard let text = searchText, !text.isEmpty else { return "Unknown item" }
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

// MARK: - Подтверждение вердикта

/// Подтверждение вердикта — дословный пункт списка с сайта (списочная
/// архитектура): цитата + секция, где она найдена. Концепция «простого
/// ответа»: других подробностей приложение не показывает.
/// Старые записи истории (СП4.1) содержали также exceptions/preparation/
/// correctedStatus — при чтении эти лишние ключи игнорируются
struct Confirmation: Codable, Equatable {
    /// Дословная цитата с сайта, подтверждающая вердикт
    let citation: String

    /// Секция сайта, где найден подтверждающий пункт.
    /// nil — старые записи истории или подтверждение без секции
    var sourceSection: String? = nil
}

// MARK: - Результат поиска (СП3, СП4)

/// Статус пригодности предмета для переработки.
/// Три исхода вердикта: да (recyclable) / нет (notRecyclable) /
/// неясно (notFound — приложение не смогло определить по спискам сайта).
/// rawValue сохраняется в истории — не менять; текст для UI — в displayText
enum RecycleStatus: String, Codable {
    case recyclable = "Recyclable"
    case notRecyclable = "Not recyclable"
    case notFound = "Not found on website"

    /// Текст статуса для интерфейса.
    /// notFound — это «неясно», а не «нет на сайте»:
    /// приложение не смогло определить пригодность
    var displayText: String {
        switch self {
        case .recyclable:
            return "Recyclable"
        case .notRecyclable:
            return "Not recyclable"
        case .notFound:
            return "Not listed on website"
        }
    }

    /// Цвет статуса — единый для всех экранов:
    /// да — зелёный; нет — приглушённый розово-терракотовый
    /// (яркий красный кричал); неясно — синий
    var color: Color {
        switch self {
        case .recyclable:
            return .green
        case .notRecyclable:
            // Кислотный циан с синим, светлее (0.12, 0.46, 0.66).
            // Другие варианты: (0.24, 0.42, 0.44) приглушённый циан,
            // (0.22, 0.22, 0.22) тёмно-серый
            return Color(red: 0.25, green: 0.60, blue: 0.78)
        case .notFound:
            return .blue
        }
    }
}

/// Результат поиска предмета на сайте
struct SearchResult: Codable {
    /// Статус пригодности. Изменяемый: при противоречии с содержимым сайта
    /// вердикт исправляется по результату анализа Claude (СП4.1)
    var status: RecycleStatus
    
    /// Текст-доказательство с сайта
    var evidence: String?
    
    /// URL изображения с сайта (если есть)
    var evidenceImageURL: String?
    
    /// URL страницы на сайте, где найден предмет
    var sourceURL: String?
    
    /// Структурированное подтверждение вердикта от Claude AI (СП4.1)
    /// — заполняется после успешного поиска (status != .notFound)
    /// — может быть nil, если получение подтверждения не удалось
    /// — старые записи в истории (созданные до СП4.1) тоже имеют nil
    var confirmation: Confirmation?
}

// MARK: - Профиль пользователя (СП6)

/// Данные пользователя, хранятся локально на устройстве
struct UserProfile: Codable {
    /// Имя пользователя
    var name: String?
    
    /// Email для получения уведомлений
    var email: String?
    
    /// Телефон
    var phone: String?
    
    /// Пустой профиль по умолчанию
    static let empty = UserProfile()
    
    /// Проверка, заполнен ли хотя бы email
    var hasEmail: Bool {
        guard let email = email else { return false }
        return !email.isEmpty
    }
}

// MARK: - История запросов

/// Запись в истории — связывает предмет с результатом проверки
struct CheckHistoryEntry: Identifiable, Codable {
    let id: UUID
    let item: RecycleItem

    /// Результат проверки. Изменяемый: после догрузки confirmation (СП4.1)
    /// запись обновляется через StorageService.updateHistoryResult
    var result: SearchResult?
    
    /// Был ли отправлен email-запрос на добавление (СП5)
    var emailSent: Bool
    
    let checkedAt: Date
    
    init(item: RecycleItem, result: SearchResult?, emailSent: Bool = false) {
        self.id = UUID()
        self.item = item
        self.result = result
        self.emailSent = emailSent
        self.checkedAt = Date()
    }
}
