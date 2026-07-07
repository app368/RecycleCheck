import Foundation

// MARK: - Конфигурация приложения
// Центральное место для всех настраиваемых параметров.
// URL сайта и email можно изменить на экране Settings.
// Значения по умолчанию задаёт программист здесь.

enum AppConfig {
    
    // MARK: - Значения по умолчанию
    
    /// URL сайта по умолчанию
    static let defaultWebsiteURL = "https://example-recycling-site.com"
    
    /// Email по умолчанию
    static let defaultRequestEmail = "info@example-recycling-site.com"
    
    // MARK: - Актуальные значения (из Settings или значения по умолчанию)
    
    /// URL сайта, на котором приложение ищет информацию о переработке
    static var recyclingWebsiteURL: String {
        let saved = UserDefaults.standard.string(forKey: "settings_website_url")
        return (saved?.isEmpty == false) ? saved! : defaultWebsiteURL
    }
    
    /// Адрес, на который отправляется запрос о ненайденном предмете
    static var requestEmail: String {
        let saved = UserDefaults.standard.string(forKey: "settings_request_email")
        return (saved?.isEmpty == false) ? saved! : defaultRequestEmail
    }
    
    /// Тема письма по умолчанию
    static let emailSubject = "Request to add an item to the recycling database"
    
    // MARK: - AI Vision API
    
    /// Ключ для доступа к сервису распознавания изображений.
    /// Реальное значение живёт в Secrets.swift (файл вне git).
    static let visionAPIKey = Secrets.visionAPIKey
    
    /// URL эндпоинта Vision API
    static let visionAPIEndpoint = "https://api.anthropic.com/v1/messages"
}
