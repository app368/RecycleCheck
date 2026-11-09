import Foundation
import AppleArchive
import System

// MARK: - Резервная копия данных: экспорт и импорт
// Экспорт собирает все данные приложения в один архив .aar (Apple Archive):
//   backup.json      — профиль, история проверок, настройки сайта (читаемый JSON)
//   site_rules.json  — база правил сайта (если собрана)
//   RecyclePhotos/   — фото проверок
// Импорт ЗАМЕНЯЕТ текущие данные содержимым архива (слияния нет).
//
// Снимок данных и запись в UserDefaults — на главном потоке (модели
// изолированы на MainActor); копирование файлов и архивация — в фоне
// (BackupArchiver), чтобы экран не замирал на сотне мегабайт фото.

// MARK: - Содержимое backup.json

/// Данные приложения, кроме файлов: профиль, история, настройки сайта
struct BackupPayload: Codable {
    /// Версия формата резервной копии — для совместимости будущих версий
    let formatVersion: Int

    /// Дата создания копии
    let createdAt: Date

    let profile: UserProfile
    let history: [CheckHistoryEntry]

    /// Настройки сайта; nil — пользователь не менял значение по умолчанию
    let websiteURL: String?
    let requestEmail: String?
}

// MARK: - Ошибки

enum BackupError: LocalizedError {
    case archiveFailed
    case notABackup
    case newerFormat

    var errorDescription: String? {
        switch self {
        case .archiveFailed:
            return "The backup file could not be created or read."
        case .notABackup:
            return "This file is not a RecycleCheck backup."
        case .newerFormat:
            return "This backup was made by a newer version of the app. Please update RecycleCheck."
        }
    }
}

// MARK: - Сервис резервной копии

final class BackupService {

    static let shared = BackupService()

    /// Текущая версия формата
    static let formatVersion = 1

    /// Ключи настроек сайта в UserDefaults (те же, что в AppConfig и SettingsView)
    private enum SettingsKeys {
        static let websiteURL = "settings_website_url"
        static let requestEmail = "settings_request_email"
    }

    private let storage = StorageService.shared
    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Экспорт

    /// Собирает архив со всеми данными приложения.
    /// - Returns: URL готового файла во временной папке (для меню «Поделиться»)
    func makeBackup() async throws -> URL {
        // Снимок данных — на главном потоке
        let payload = BackupPayload(
            formatVersion: Self.formatVersion,
            createdAt: Date(),
            profile: storage.loadProfile(),
            history: storage.loadHistory(),
            websiteURL: defaults.string(forKey: SettingsKeys.websiteURL),
            requestEmail: defaults.string(forKey: SettingsKeys.requestEmail)
        )
        let json = try Self.makeEncoder().encode(payload)

        let photosFolder = storage.photosDirectory
        let rulesFile = storage.siteRulesFileURL
        let fileName = "RecycleCheck-backup-\(Self.dateStamp()).aar"

        // Копирование файлов и архивация — в фоне
        return try await Task.detached {
            try BackupArchiver.writeArchive(
                json: json, photosFolder: photosFolder,
                rulesFile: rulesFile, fileName: fileName
            )
        }.value
    }

    // MARK: - Импорт

    /// Заменяет все данные приложения содержимым архива.
    /// - Parameter archiveURL: файл, выбранный пользователем (доступ уже открыт)
    func restoreBackup(from archiveURL: URL) async throws {
        // Распаковка — в фоне
        let folder = try await Task.detached {
            try BackupArchiver.extract(archiveURL)
        }.value
        defer { try? FileManager.default.removeItem(at: folder) }

        // Проверка: это наша копия и формат нам понятен
        guard let json = try? Data(contentsOf: folder.appendingPathComponent(BackupArchiver.payloadName)),
              let payload = try? Self.makeDecoder().decode(BackupPayload.self, from: json) else {
            throw BackupError.notABackup
        }
        guard payload.formatVersion <= Self.formatVersion else {
            throw BackupError.newerFormat
        }

        // Файлы — фото и база правил — заменяются в фоне
        let photosFolder = storage.photosDirectory
        let rulesFile = storage.siteRulesFileURL
        try await Task.detached {
            try BackupArchiver.replaceFiles(
                from: folder, photosFolder: photosFolder, rulesFile: rulesFile
            )
        }.value

        // Профиль, история и настройки — на главном потоке
        storage.saveProfile(payload.profile)
        storage.saveHistory(payload.history)
        setOrRemove(payload.websiteURL, forKey: SettingsKeys.websiteURL)
        setOrRemove(payload.requestEmail, forKey: SettingsKeys.requestEmail)
    }

    // MARK: - Вспомогательное

    /// Значение настройки из копии; nil — вернуть значение по умолчанию
    private func setOrRemove(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// JSON с датами ISO 8601 и отступами — файл удобно читать на Mac
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Дата для имени файла: 2026-11-08
    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

// MARK: - Работа с файлами и архивом (фоновые операции)

nonisolated enum BackupArchiver {

    /// Имя файла с данными внутри архива
    static let payloadName = "backup.json"

    /// Имена файлов и папок внутри архива
    private static let rulesName = "site_rules.json"
    private static let photosName = "RecyclePhotos"

    private static var fileManager: FileManager { .default }

    // MARK: - Запись архива

    /// Складывает данные во временную папку и упаковывает её в архив
    static func writeArchive(json: Data, photosFolder: URL, rulesFile: URL, fileName: String) throws -> URL {
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("backup-staging-\(UUID().uuidString)")
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        try json.write(to: staging.appendingPathComponent(payloadName))
        if fileManager.fileExists(atPath: rulesFile.path) {
            try fileManager.copyItem(at: rulesFile, to: staging.appendingPathComponent(rulesName))
        }
        if fileManager.fileExists(atPath: photosFolder.path) {
            try fileManager.copyItem(at: photosFolder, to: staging.appendingPathComponent(photosName))
        }

        let archiveURL = fileManager.temporaryDirectory.appendingPathComponent(fileName)
        try? fileManager.removeItem(at: archiveURL)
        try compress(folder: staging, to: archiveURL)
        return archiveURL
    }

    /// Упаковка папки в .aar (сжатие LZFSE)
    private static func compress(folder: URL, to archiveURL: URL) throws {
        guard let fileStream = ArchiveByteStream.fileStream(
                path: FilePath(archiveURL.path), mode: .writeOnly,
                options: [.create, .truncate], permissions: FilePermissions(rawValue: 0o644)),
              let compressStream = ArchiveByteStream.compressionStream(using: .lzfse, writingTo: fileStream),
              let encodeStream = ArchiveStream.encodeStream(writingTo: compressStream),
              let keySet = ArchiveHeader.FieldKeySet("TYP,PAT,LNK,DAT,MOD,MTM") else {
            throw BackupError.archiveFailed
        }
        // Потоки закрываются от внутреннего к внешнему
        defer {
            try? encodeStream.close()
            try? compressStream.close()
            try? fileStream.close()
        }
        try encodeStream.writeDirectoryContents(archiveFrom: FilePath(folder.path), keySet: keySet)
    }

    // MARK: - Распаковка

    /// Распаковывает архив во временную папку и возвращает её URL
    static func extract(_ archiveURL: URL) throws -> URL {
        let folder = fileManager.temporaryDirectory
            .appendingPathComponent("backup-restore-\(UUID().uuidString)")
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        guard let fileStream = ArchiveByteStream.fileStream(
                path: FilePath(archiveURL.path), mode: .readOnly,
                options: [], permissions: FilePermissions(rawValue: 0o644)),
              let decompressStream = ArchiveByteStream.decompressionStream(readingFrom: fileStream),
              let decodeStream = ArchiveStream.decodeStream(readingFrom: decompressStream),
              let extractStream = ArchiveStream.extractStream(
                extractingTo: FilePath(folder.path), flags: [.ignoreOperationNotPermitted]) else {
            try? fileManager.removeItem(at: folder)
            throw BackupError.notABackup
        }
        defer {
            try? extractStream.close()
            try? decodeStream.close()
            try? decompressStream.close()
            try? fileStream.close()
        }
        do {
            _ = try ArchiveStream.process(readingFrom: decodeStream, writingTo: extractStream)
        } catch {
            try? fileManager.removeItem(at: folder)
            throw BackupError.notABackup
        }
        return folder
    }

    // MARK: - Замена файлов приложения

    /// Заменяет фото и базу правил содержимым распакованной копии.
    /// Чего нет в копии — удаляется: импорт заменяет данные целиком
    static func replaceFiles(from folder: URL, photosFolder: URL, rulesFile: URL) throws {
        try replace(photosFolder, with: folder.appendingPathComponent(photosName))
        try replace(rulesFile, with: folder.appendingPathComponent(rulesName))
    }

    /// Удаляет текущий файл/папку и переносит на его место новый (если есть)
    private static func replace(_ target: URL, with source: URL) throws {
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
        if fileManager.fileExists(atPath: source.path) {
            try fileManager.moveItem(at: source, to: target)
        }
    }
}
