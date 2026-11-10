import SwiftUI

// MARK: - Экран «Reply from the site» — ответ города по проверке
// Открывается из деталей проверки, по которой был отправлен вопрос.
// Пользователь вставляет текст письма → Claude делает черновики пунктов
// (CityAnswerExtractionService) → пользователь правит/удаляет → Save.
// Сохранённые пункты учитываются при следующих проверках (VerdictService).

struct CityReplyView: View {

    /// Проверка, по которой был задан вопрос
    let entry: CheckHistoryEntry

    @Environment(\.dismiss) private var dismiss

    @State private var replyText = ""
    @State private var drafts: [CityAnswerRule] = []
    @State private var isCreating = false
    @State private var errorMessage: String?

    /// Сиреневый акцент — всё, что делает ИИ (как на экране распознавания)
    private let accent = Color(red: 0.62, green: 0.46, blue: 0.86)

    private var canCreate: Bool {
        !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCreating
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Предмет: маленькое фото и название
                Section {
                    HStack(spacing: 12) {
                        itemThumbnail
                        Text(entry.item.displayName)
                            .font(.headline)
                    }
                }

                // MARK: - Текст письма
                Section {
                    TextEditor(text: $replyText)
                        .frame(minHeight: 160)
                        .overlay(alignment: .topLeading) {
                            if replyText.isEmpty {
                                Text("Paste the reply here")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("Reply from the site team")
                }

                // MARK: - Черновики пунктов делает ИИ
                Section {
                    Button {
                        createRules()
                    } label: {
                        HStack {
                            Spacer()
                            if isCreating {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Create rules")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                        .foregroundStyle(.white)
                    }
                    .listRowBackground(canCreate || isCreating ? accent : accent.opacity(0.4))
                    .disabled(!canCreate)
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                // MARK: - Черновики: текст можно править, лишнее — смахнуть
                if !drafts.isEmpty {
                    Section {
                        ForEach($drafts) { $rule in
                            DraftRuleRow(rule: $rule)
                        }
                        .onDelete { drafts.remove(atOffsets: $0) }
                    } header: {
                        Text("Rules")
                    } footer: {
                        Text("Swipe left to remove a rule. You can edit the item text.")
                    }
                }
            }
            .navigationTitle("Reply from the site")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        StorageService.shared.addCityAnswers(drafts)
                        dismiss()
                    } label: {
                        Text("Save")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.green)
                    .disabled(drafts.isEmpty)
                }
            }
        }
    }

    // MARK: - Маленькое фото предмета

    @ViewBuilder
    private var itemThumbnail: some View {
        if let fileName = entry.item.photoFileName,
           let image = StorageService.shared.loadPhoto(named: fileName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Черновики из письма

    private func createRules() {
        isCreating = true
        errorMessage = nil
        Task {
            do {
                drafts = try await CityAnswerExtractionService.shared.draftRules(
                    fromReply: replyText, item: entry.item, historyEntryID: entry.id
                )
            } catch let error as CityAnswerExtractionService.ExtractionError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = friendlyError(from: error).message
            }
            isCreating = false
        }
    }
}

// MARK: - Строка черновика: метка «можно/нельзя», пункт, цитата из письма

struct DraftRuleRow: View {

    @Binding var rule: CityAnswerRule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CityVerdictBadge(verdict: rule.verdict)
            TextField("Item", text: $rule.itemText, axis: .vertical)
                .font(.body)
                .fontWeight(.semibold)
            Text("\u{201C}\(rule.quote)\u{201D}")
                .font(.footnote)
                .italic()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Метка «Allowed / Not allowed» в цветах статусов приложения

struct CityVerdictBadge: View {

    let verdict: RuleVerdict

    var body: some View {
        Text(verdict == .allowed ? "Allowed" : "Not allowed")
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(verdict == .allowed ? RecycleStatus.recyclable.color : RecycleStatus.notRecyclable.color)
            .clipShape(Capsule())
    }
}

// MARK: - Строка ответа города в Settings: метка, пункт, цитата, дата

struct CityAnswerRow: View {

    let rule: CityAnswerRule

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CityVerdictBadge(verdict: rule.verdict)
            Text(rule.itemText)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("\u{201C}\(rule.quote)\u{201D}")
                .font(.footnote)
                .italic()
                .foregroundStyle(.secondary)
            Text(rule.sourceLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
