import SwiftUI

// MARK: - Секция подтверждения вердикта (СП4.1, шаг 3)
// Переиспользуемый компонент для ResultView и HistoryDetailView.
// Отображает структурированное подтверждение из трёх подразделов:
// Citation from website / Exceptions / How to prepare.
// Поддерживает три состояния: загрузка, готово, недоступно.

/// Состояние секции подтверждения
enum ConfirmationState: Equatable {
    /// Идёт сбор упоминаний и анализ (Collector + Service)
    case loading

    /// Подтверждение получено
    case loaded(Confirmation)

    /// Получить подтверждение не удалось
    case unavailable
}

struct ConfirmationSectionView: View {

    /// Текущее состояние секции
    let state: ConfirmationState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // MARK: - Заголовок секции

            Label {
                Text("Confirmation")
            } icon: {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
            .font(.title3)
            .fontWeight(.semibold)

            // MARK: - Содержимое по состоянию

            switch state {
            case .loading:
                loadingView
            case .loaded(let confirmation):
                subsections(for: confirmation)
            case .unavailable:
                unavailableView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Индикатор загрузки

    private var loadingView: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Looking for confirmation…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding()
        .background(.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Сообщение о недоступности

    private var unavailableView: some View {
        Text("Confirmation unavailable")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding()
            .background(.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Три подраздела подтверждения

    @ViewBuilder
    private func subsections(for confirmation: Confirmation) -> some View {
        // Цитата с сайта — есть всегда
        subsection(
            title: "Citation from website",
            icon: "text.quote",
            color: .blue,
            text: confirmation.citation
        )

        // Подразделы со значением "Not applicable" скрываем — информации не несут.
        // Значения "No exceptions mentioned" / "No preparation instructions found"
        // показываем: они информативны для пользователя.
        if let exceptions = displayableValue(confirmation.exceptions) {
            subsection(
                title: "Exceptions",
                icon: "exclamationmark.triangle.fill",
                color: .orange,
                text: exceptions
            )
        }

        if let preparation = displayableValue(confirmation.preparation) {
            subsection(
                title: "How to prepare",
                icon: "wrench.and.screwdriver.fill",
                color: .teal,
                text: preparation
            )
        }
    }

    /// Один подраздел: заголовок с цветной иконкой + текст на подложке
    private func subsection(title: String, icon: String, color: Color, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
            .font(.subheadline)
            .fontWeight(.semibold)

            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Значение для отображения: nil, если поле равно "Not applicable" или пусто
    private func displayableValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.lowercased() != "not applicable" else {
            return nil
        }
        return trimmed
    }
}

// MARK: - Кнопка «Show raw evidence» (сырой текст с сайта)
// Оформлена как заметная кнопка-карточка с разворачиванием.
// Используется в ResultView и HistoryDetailView.

struct RawEvidenceDisclosure: View {

    /// Сырой текст-доказательство с сайта
    let evidence: String

    /// Развёрнуто ли содержимое
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(evidence)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        } label: {
            Label("Show raw evidence", systemImage: "doc.text.magnifyingglass")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.blue)
        }
        .tint(.blue)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Превью

#Preview("Raw evidence button") {
    RawEvidenceDisclosure(
        evidence: "Plastic bottles (PET #1) are widely accepted in curbside recycling programs. Rinse and remove the cap before placing in the recycling bin."
    )
    .padding()
}

#Preview("Loaded — recyclable") {
    ScrollView {
        ConfirmationSectionView(
            state: .loaded(Confirmation(
                citation: "Cartons (milk, juice, soup; empty and dry) go in your blue recycling bin.",
                exceptions: "No exceptions mentioned",
                preparation: "Empty and dry the carton before placing it in the bin."
            ))
        )
        .padding()
    }
}

#Preview("Loaded — not recyclable") {
    ScrollView {
        ConfirmationSectionView(
            state: .loaded(Confirmation(
                citation: "NO drinking glasses, dishware, or drinkware of any kind.",
                exceptions: "Not applicable",
                preparation: "Not applicable"
            ))
        )
        .padding()
    }
}

#Preview("Loading") {
    ConfirmationSectionView(state: .loading)
        .padding()
}

#Preview("Unavailable") {
    ConfirmationSectionView(state: .unavailable)
        .padding()
}
