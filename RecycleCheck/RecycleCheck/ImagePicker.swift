import SwiftUI
import UIKit

// MARK: - Обёртка камеры для SwiftUI
// UIImagePickerController не имеет нативного SwiftUI-аналога,
// поэтому оборачиваем его через UIViewControllerRepresentable.
// Поддерживает камеру и галерею.

struct ImagePicker: UIViewControllerRepresentable {
    
    /// Источник изображения: камера или галерея
    let sourceType: UIImagePickerController.SourceType
    
    /// Замыкание, вызываемое при выборе изображения
    var onImagePicked: (UIImage) -> Void
    
    /// Замыкание при отмене
    var onCancel: () -> Void = {}
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, onCancel: onCancel)
    }
    
    // MARK: - Координатор для обработки событий делегата
    
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        
        let onImagePicked: (UIImage) -> Void
        let onCancel: () -> Void
        
        init(onImagePicked: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImagePicked = onImagePicked
            self.onCancel = onCancel
        }
        
        /// Пользователь выбрал изображение
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImagePicked(image)
            }
            picker.dismiss(animated: true)
        }
        
        /// Пользователь отменил выбор
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
            picker.dismiss(animated: true)
        }
    }
}
