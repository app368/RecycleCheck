import SwiftUI
import UIKit

// MARK: - Переиспользуемый зум фотографии (общий функционал)
// Единый компонент для всех мест приложения, где показывается фото:
// экран результата, детали истории, превью письма, экран съёмки.
// Тап по миниатюре открывает фото на весь экран с щипковым зумом,
// панорамой и двойным тапом — родное поведение через UIScrollView.
// Появление — родной зум-переход (iOS 18+): окно визуально вырастает
// из миниатюры и сворачивается обратно, а не выезжает снизу.
//
// Подключение: к любой вьюхе-миниатюре добавить `.zoomablePhoto(uiImage)`.

extension View {
    /// Делает вьюху нажимаемой: тап открывает фото на весь экран с зумом.
    /// Если image == nil — модификатор ничего не меняет
    func zoomablePhoto(_ image: UIImage?) -> some View {
        modifier(ZoomablePhotoModifier(image: image))
    }
}

// MARK: - Модификатор: тап по миниатюре → полноэкранный просмотр

private struct ZoomablePhotoModifier: ViewModifier {
    let image: UIImage?

    @State private var showViewer = false

    /// Пространство имён зум-перехода: связывает миниатюру-источник
    /// и полноэкранное окно, чтобы система анимировала одно в другое
    @Namespace private var zoomNamespace

    /// Идентификатор источника перехода внутри пространства имён
    private static let sourceID = "photo"

    func body(content: Content) -> some View {
        content
            // Вся область миниатюры реагирует на тап
            .contentShape(Rectangle())
            .onTapGesture {
                if image != nil { showViewer = true }
            }
            // Миниатюра — источник зум-перехода: из неё окно вырастает
            .matchedTransitionSource(id: Self.sourceID, in: zoomNamespace)
            .fullScreenCover(isPresented: $showViewer) {
                if let image {
                    FullScreenPhotoViewer(image: image)
                        // Появление увеличением из миниатюры, а не выездом снизу
                        .navigationTransition(.zoom(sourceID: Self.sourceID, in: zoomNamespace))
                }
            }
    }
}

// MARK: - Полноэкранный просмотрщик с зумом

struct FullScreenPhotoViewer: View {
    let image: UIImage

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            ZoomableScrollView(image: image)
                .ignoresSafeArea()

            // Кнопка закрытия — поверх изображения
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding()
            }
            .accessibilityLabel("Close")
        }
    }
}

// MARK: - Мост к UIScrollView для щипкового зума

/// Обёртка UIScrollView + UIImageView: щипковый зум, панорама,
/// двойной тап (приблизить / вернуть). Родное поведение iOS
private struct ZoomableScrollView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        // Привязываем картинку к границам скролла через Auto Layout:
        // размер приходит от системы раскладки, а не читается «на лету»
        // в makeUIView (где bounds ещё нулевые — отсюда была чёрная область).
        // При zoomScale=1 картинка равна видимой области, aspectFit центрирует
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        // Двойной тап — приблизить/вернуть
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        // Раскладка держится на Auto Layout — обновление не требуется
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                // Уже приближено — возвращаем к исходному
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                // Приближаем к точке двойного тапа
                let point = gesture.location(in: imageView)
                let targetScale = min(scrollView.maximumZoomScale, 2.5)
                let size = scrollView.bounds.size
                let width = size.width / targetScale
                let height = size.height / targetScale
                let rect = CGRect(
                    x: point.x - width / 2,
                    y: point.y - height / 2,
                    width: width,
                    height: height
                )
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}

#Preview {
    if let image = UIImage(systemName: "photo") {
        FullScreenPhotoViewer(image: image)
    }
}
