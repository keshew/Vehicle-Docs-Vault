import SwiftUI
import UIKit
import Combine
import UserNotifications

@MainActor
final class VaultNotificationInbox: ObservableObject {
    static let shared = VaultNotificationInbox()
    @Published var recordID: UUID?
}

final class VaultNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = VaultNotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let value = response.notification.request.content.userInfo["recordID"] as? String
            ?? String(response.notification.request.identifier.prefix(36))
        if let id = UUID(uuidString: value) { Task { @MainActor in VaultNotificationInbox.shared.recordID = id } }
        completionHandler()
    }
}

@MainActor
enum VaultNotificationPresenter {
    static func present(recordID: UUID, store: VaultStore) -> Bool {
        guard store.record(recordID) != nil else { store.errorMessage = "This notification refers to a record that has been removed."; return true }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter { $0.activationState == .foregroundActive }
        guard let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow), var presenter = window.rootViewController else { return false }
        while let presented = presenter.presentedViewController { presenter = presented }
        guard !presenter.isBeingDismissed, !presenter.isBeingPresented, presenter.viewIfLoaded?.window != nil else { return false }
        let content = NavigationStack {
            RecordDetail(recordID: recordID).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { [weak presenter] in presenter?.dismiss(animated: true) } }
            }
        }.environmentObject(store).environment(\.locale, Locale(identifier: "en_US")).preferredColorScheme(store.colorScheme).tint(.vaultGold).vaultErrorBanner()
        let controller = UIHostingController(rootView: content)
        controller.modalPresentationStyle = .pageSheet
        controller.sheetPresentationController?.detents = [.large()]
        controller.sheetPresentationController?.prefersGrabberVisible = true
        presenter.present(controller, animated: true)
        return true
    }
}
