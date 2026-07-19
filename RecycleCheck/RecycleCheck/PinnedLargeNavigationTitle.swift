import SwiftUI

// MARK: - Общий закреплённый крупный заголовок страницы

private struct PinnedLargeNavigationTitleModifier<Accessory: View>: ViewModifier {
    let title: LocalizedStringKey
    @ViewBuilder let accessory: () -> Accessory

    func body(content: Content) -> some View {
        content
            // Системный large title сворачивается при прокрутке, поэтому
            // навбар оставляем для кнопок, а заголовок показываем отдельно.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaBar(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Text(title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                        .accessibilityAddTraits(.isHeader)

                    accessory()
                }
            }
    }
}

extension View {
    /// Показывает крупный заголовок, который остаётся закреплённым и не
    /// уменьшается, пока содержимое страницы прокручивается под ним.
    func pinnedLargeNavigationTitle(
        _ title: LocalizedStringKey
    ) -> some View {
        modifier(
            PinnedLargeNavigationTitleModifier(title: title) {
                EmptyView()
            }
        )
    }

    /// Вариант с дополнительным содержимым под заголовком, например баннером.
    func pinnedLargeNavigationTitle<Accessory: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) -> some View {
        modifier(
            PinnedLargeNavigationTitleModifier(
                title: title,
                accessory: accessory
            )
        )
    }
}
