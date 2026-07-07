import Foundation
import UIKit

// MARK: - Сервис локального хранения данных
// Отвечает за сохранение и загрузку данных на устройстве:
// профиль пользователя, история проверок, фотографии.
// Серверной базы данных нет — всё хранится локально.

final class StorageService {
    
    static let shared = StorageService()
    
    private let defaults = UserDefaults.standard
    
    // Ключи для UserDefaults
    private enum Keys {
        static let userProfile = "recyclecheck_user_profile"
        static let checkHistory = "recyclecheck_check_history"
        static let cachedTargetURLs = "recyclecheck_cached_target_urls"
        static let cachedBaseURL = "recyclecheck_cached_base_url"
        static let cachedTargetURLsDate = "recyclecheck_cached_target_urls_date"
    }
    
    private init() {}
    
    // MARK: - Профиль пользователя (СП6)
    
    /// Сохранение профиля пользователя
    func saveProfile(_ profile: UserProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: Keys.userProfile)
        }
    }
    
    /// Загрузка профиля пользователя
    func loadProfile() -> UserProfile {
        guard let data = defaults.data(forKey: Keys.userProfile),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else {
            return .empty
        }
        return profile
    }
    
    // MARK: - История проверок
    
    /// Сохранение истории проверок
    func saveHistory(_ history: [CheckHistoryEntry]) {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: Keys.checkHistory)
        }
    }
    
    /// Загрузка истории проверок
    func loadHistory() -> [CheckHistoryEntry] {
        guard let data = defaults.data(forKey: Keys.checkHistory),
              let history = try? JSONDecoder().decode([CheckHistoryEntry].self, from: data) else {
            return []
        }
        return history
    }
    
    /// Добавление записи в историю
    func addHistoryEntry(_ entry: CheckHistoryEntry) {
        var history = loadHistory()
        history.insert(entry, at: 0) // Новые записи — в начало
        saveHistory(history)
    }

    /// Обновление результата записи истории по id (СП4.1)
    /// Используется для дозаписи confirmation после его догрузки в ResultView
    func updateHistoryResult(entryID: UUID, result: SearchResult) {
        var history = loadHistory()
        guard let index = history.firstIndex(where: { $0.id == entryID }) else { return }
        history[index].result = result
        saveHistory(history)
    }
    
    // MARK: - Удаление записей из истории (СП7.3)
    
    /// Удаление одной записи по ID, включая связанное фото
    func deleteHistoryEntry(id: UUID) {
        var history = loadHistory()
        if let index = history.firstIndex(where: { $0.id == id }) {
            // Удаляем фото из FileManager, если есть
            if let photoFileName = history[index].item.photoFileName {
                deletePhoto(named: photoFileName)
            }
            history.remove(at: index)
            saveHistory(history)
        }
    }
    
    /// Удаление нескольких записей по набору ID
    func deleteHistoryEntries(ids: Set<UUID>) {
        var history = loadHistory()
        // Сначала удаляем фото для каждой записи
        for entry in history where ids.contains(entry.id) {
            if let photoFileName = entry.item.photoFileName {
                deletePhoto(named: photoFileName)
            }
        }
        // Удаляем записи из массива
        history.removeAll { ids.contains($0.id) }
        saveHistory(history)
    }
    
    /// Удаление всех записей из истории и всех фото
    func deleteAllHistory() {
        let history = loadHistory()
        // Удаляем все фото
        for entry in history {
            if let photoFileName = entry.item.photoFileName {
                deletePhoto(named: photoFileName)
            }
        }
        // Очищаем историю
        saveHistory([])
    }
    
    // MARK: - Фотографии
    
    /// Папка для хранения фотографий
    private var photosDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let photosPath = documentsPath.appendingPathComponent("RecyclePhotos")
        
        // Создаём папку, если её нет
        if !FileManager.default.fileExists(atPath: photosPath.path) {
            try? FileManager.default.createDirectory(at: photosPath, withIntermediateDirectories: true)
        }
        
        return photosPath
    }
    
    /// Сохранение фотографии, возвращает имя файла
    func savePhoto(_ image: UIImage) -> String? {
        let fileName = UUID().uuidString + ".jpg"
        let filePath = photosDirectory.appendingPathComponent(fileName)
        
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            return nil
        }
        
        do {
            try data.write(to: filePath)
            return fileName
        } catch {
            print("Ошибка сохранения фото: \(error)")
            return nil
        }
    }
    
    /// Загрузка фотографии по имени файла
    func loadPhoto(named fileName: String) -> UIImage? {
        let filePath = photosDirectory.appendingPathComponent(fileName)
        return UIImage(contentsOfFile: filePath.path)
    }
    
    /// Получение данных фотографии для отправки по email (СП5)
    func photoData(named fileName: String) -> Data? {
        let filePath = photosDirectory.appendingPathComponent(fileName)
        return try? Data(contentsOf: filePath)
    }
    
    /// Удаление фотографии по имени файла
    private func deletePhoto(named fileName: String) {
        let filePath = photosDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: filePath)
    }
    
    // MARK: - Кэш целевых страниц сайта (СП3.3)
    
    /// Сохранение списка целевых URL для указанного базового URL сайта.
    /// Ключ кэша хранится в нормализованном виде, дата сборки — рядом
    func saveTargetURLs(_ urls: [String], forBaseURL baseURL: String) {
        defaults.set(urls, forKey: Keys.cachedTargetURLs)
        defaults.set(URLNormalizer.normalize(baseURL), forKey: Keys.cachedBaseURL)
        defaults.set(Date(), forKey: Keys.cachedTargetURLsDate)
    }

    /// Дата последней сборки кэша целевых URL.
    /// nil — кэш пуст или собран до появления датировки
    func targetURLsCacheDate() -> Date? {
        defaults.object(forKey: Keys.cachedTargetURLsDate) as? Date
    }

    /// Загрузка списка целевых URL из кэша.
    /// Возвращает nil, если кэш пуст или baseURL изменился.
    /// Ключи сравниваются в нормализованном виде — сырой ключ,
    /// сохранённый до появления нормализации, тоже матчится
    func loadTargetURLs(forBaseURL baseURL: String) -> [String]? {
        guard let cachedBase = defaults.string(forKey: Keys.cachedBaseURL),
              URLNormalizer.normalize(cachedBase) == URLNormalizer.normalize(baseURL) else {
            return nil
        }
        return defaults.stringArray(forKey: Keys.cachedTargetURLs)
    }
    
    /// Очистка кэша целевых URL (при смене сайта)
    func clearTargetURLsCache() {
        defaults.removeObject(forKey: Keys.cachedTargetURLs)
        defaults.removeObject(forKey: Keys.cachedBaseURL)
        defaults.removeObject(forKey: Keys.cachedTargetURLsDate)
    }
}
