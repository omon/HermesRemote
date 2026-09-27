import SwiftTerm
import SwiftUI
import UIKit

@MainActor
struct TerminalContainer: UIViewRepresentable {
    let service: SSHService

    func makeCoordinator() -> Coordinator { Coordinator(service: service) }

    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero, font: .monospacedSystemFont(ofSize: 13, weight: .regular))
        view.terminalDelegate = context.coordinator
        view.nativeBackgroundColor = .black
        view.nativeForegroundColor = .white
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        // SwiftTerm標準のアクセサリ列はアプリ独自の補助キー列と重複するため使わない。
        view.inputAccessoryView = nil
        service.setTerminalFeed { [weak view] bytes in view?.feed(byteArray: bytes[...]) }
        service.setTerminalFocus { [weak view] in
            guard let view else { return }
            _ = view.becomeFirstResponder()
            view.reloadInputViews()
        }
        service.setTerminalDismissKeyboard { [weak view] in
            _ = view?.resignFirstResponder()
        }
        return view
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {}

    static func dismantleUIView(_ uiView: TerminalView, coordinator: Coordinator) {
        coordinator.service.clearTerminalFeed()
        coordinator.service.clearTerminalFocus()
        coordinator.service.clearTerminalDismissKeyboard()
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency TerminalViewDelegate {
        let service: SSHService
        init(service: SSHService) { self.service = service }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            service.resize(columns: newCols, rows: newRows,
                pixelWidth: Int(source.bounds.width), pixelHeight: Int(source.bounds.height))
        }
        func setTerminalTitle(source: TerminalView, title: String) { service.updateTerminalTitle(title) }
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func send(source: TerminalView, data: ArraySlice<UInt8>) { service.send(Array(data)) }
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
            UIApplication.shared.open(url)
        }
        func bell(source: TerminalView) { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        func clipboardCopy(source: TerminalView, content: Data) {
            UIPasteboard.general.string = String(data: content, encoding: .utf8)
        }
        func clipboardRead(source: TerminalView) -> Data? { UIPasteboard.general.string?.data(using: .utf8) }
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
