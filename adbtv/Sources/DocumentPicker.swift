import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 用 UIDocumentPicker 代替 SwiftUI 的 fileImporter：
/// asCopy = true 会把文件复制到 App 沙盒，避免「文件提供器不支持就地访问」导致点了没反应；
/// 类型用 .item，不做任何过滤，.apk 这种系统不认识的类型也能选。
struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        vc.allowsMultipleSelection = false
        vc.shouldShowFileExtensions = true
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}
