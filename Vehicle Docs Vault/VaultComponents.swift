import SwiftUI
import UIKit

extension Color {
    static let vaultNavy = Color(red: 0.045, green: 0.075, blue: 0.105)
    static let vaultBlue = Color(red: 0.23, green: 0.39, blue: 0.64)
    static let vaultGold = adaptive(light: UIColor(red: 0.57, green: 0.43, blue: 0.24, alpha: 1), dark: UIColor(red: 0.80, green: 0.69, blue: 0.49, alpha: 1))
    static let vaultChampagne = Color(red: 0.81, green: 0.72, blue: 0.56)
    static let vaultInk = adaptive(light: UIColor(red: 0.09, green: 0.13, blue: 0.16, alpha: 1), dark: UIColor(red: 0.91, green: 0.92, blue: 0.91, alpha: 1))
    static let vaultBackground = adaptive(light: UIColor(red: 0.958, green: 0.950, blue: 0.931, alpha: 1), dark: UIColor(red: 0.047, green: 0.061, blue: 0.074, alpha: 1))
    static let vaultCard = adaptive(light: UIColor(red: 0.995, green: 0.990, blue: 0.978, alpha: 1), dark: UIColor(red: 0.080, green: 0.098, blue: 0.115, alpha: 1))
    static let vaultLine = adaptive(light: UIColor(red: 0.12, green: 0.16, blue: 0.18, alpha: 0.09), dark: UIColor(white: 1, alpha: 0.09))
    static let vaultCanvasText = adaptive(light: UIColor(red: 0.99, green: 0.98, blue: 0.95, alpha: 1), dark: UIColor(red: 0.06, green: 0.08, blue: 0.10, alpha: 1))
    private static func adaptive(light: UIColor, dark: UIColor) -> Color { Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light }) }
}

struct VaultCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.vaultCard, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.vaultLine, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.025), radius: 18, x: 0, y: 7)
    }
}

struct EmptyVault: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        VStack(spacing: 17) {
            ZStack {
                Circle().stroke(Color.vaultGold.opacity(0.14), lineWidth: 1).frame(width: 108, height: 108)
                Circle().stroke(Color.vaultGold.opacity(0.20), lineWidth: 1).frame(width: 82, height: 82)
                Image(systemName: symbol).font(.system(size: 28, weight: .ultraLight)).foregroundStyle(Color.vaultGold)
                Circle().fill(Color.vaultGold).frame(width: 5, height: 5).offset(x: 47, y: -24)
            }.padding(.bottom, 6).accessibilityHidden(true)
            Text(title).font(.vaultDisplay(27)).tracking(-0.6).multilineTextAlignment(.center).foregroundStyle(Color.vaultInk)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4).frame(maxWidth: 300)
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(VaultPrimaryButton()).padding(.top, 8) }
        }.padding(.horizontal, 24).padding(.vertical, 34).frame(maxWidth: .infinity)
    }
}

struct VaultPrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold)).foregroundStyle(Color.vaultCanvasText)
            .padding(.horizontal, 24).padding(.vertical, 18).background(Color.vaultInk.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.vaultGold.opacity(0.25), lineWidth: 1)).opacity(enabled ? 1 : 0.35)
    }
}

struct StatusPill: View {
    var value: String
    var color: Color {
        switch value {
        case "Expired", "Past", "Removed", "Retired": return .red
        case "Expiring Soon", "Stored": return .orange
        case "Installed", "Active", "Completed": return .teal
        default: return .secondary
        }
    }
    var body: some View {
        if !value.isEmpty {
            HStack(spacing: 5) { Circle().fill(color).frame(width: 4, height: 4); Text(value).font(.caption2.weight(.medium)) }
                .padding(.horizontal, 8).padding(.vertical, 6).foregroundStyle(color).background(color.opacity(0.065), in: Capsule())
        }
    }
}

struct RecordRow: View {
    @EnvironmentObject var store: VaultStore
    @Environment(\.dynamicTypeSize) private var typeSize
    var record: VaultRecord
    var showVehicle = false
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: record.kind.symbol).font(.system(size: 20, weight: .light)).foregroundStyle(Color.vaultGold)
                .frame(width: 46, height: 52).background(Color.vaultGold.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.vaultGold.opacity(0.14), lineWidth: 0.7))
            VStack(alignment: .leading, spacing: 5) {
                Text(record.displayTitle).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                if showVehicle { Text(store.vehicle(record.vehicleID)?.title ?? "Vehicle").font(.caption).foregroundStyle(.secondary) }
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if typeSize.isAccessibilitySize && [.document, .part, .tire, .reminder].contains(record.kind) { StatusPill(value: record.computedStatus) }
            }
            Spacer(minLength: 4)
            if !typeSize.isAccessibilitySize && [.document, .part, .tire, .reminder].contains(record.kind) { StatusPill(value: record.computedStatus) }
        }.padding(.vertical, 10)
    }
    var subtitle: String {
        switch record.kind {
        case .document: return record.category + " · " + (record.expiration.map { store.date($0) } ?? "No expiration")
        case .part: return [record["manufacturer"], record["partNumber"], record.category].filter { !$0.isEmpty }.joined(separator: " · ")
        case .tire: return [record["manufacturer"], record["model"], record.tireSize, record.category].filter { !$0.isEmpty }.joined(separator: " · ")
        case .replacement, .tireChange: return store.date(record.date) + (record["mileage"].isEmpty ? "" : " · \(record["mileage"]) \(record["distanceUnit"].isEmpty ? store.distanceSuffix : record["distanceUnit"])")
        case .reminder: return store.date(record.date) + " · " + record.date.vaultTime
        case .note: return record.category + " · " + store.date(record.date)
        }
    }
}

struct VehicleThumbnail: View {
    @EnvironmentObject var store: VaultStore
    var vehicle: Vehicle
    var size: CGFloat = 64
    var body: some View {
        Group {
            if let id = vehicle.coverID, let item = store.database.attachments.first(where: { $0.id == id }) {
                VaultMediaImage(url: store.fileURL(item), pixels: 240) { vehiclePlaceholder }
            } else {
                vehiclePlaceholder
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.24))
    }
    private var vehiclePlaceholder: some View {
        ZStack {
            Color.vaultNavy
            if vehicle.type == "Car" || vehicle.type == "Other" { AutomotiveSilhouette().padding(size * 0.05) }
            else { Image(systemName: vehicle.type == "Motorcycle" ? "bicycle" : "truck.box").font(.system(size: size * 0.4, weight: .ultraLight)).foregroundStyle(Color.vaultChampagne) }
        }
    }
}

struct VehicleMenu: View {
    @EnvironmentObject var store: VaultStore
    var body: some View {
        Menu {
            ForEach(store.activeVehicles) { vehicle in
                Button { store.selectVehicle(vehicle.id) } label: {
                    Label(vehicle.title, systemImage: store.selectedVehicle?.id == vehicle.id ? "checkmark.circle.fill" : "car")
                }
            }
            Divider()
            NavigationLink { VehiclesView() } label: { Label("Manage Vehicles", systemImage: "square.stack.3d.up") }
        } label: {
            HStack(spacing: 5) { Image(systemName: "car.side"); Text(store.selectedVehicle?.title ?? "Select vehicle").lineLimit(1); Image(systemName: "chevron.down").font(.caption2) }.font(.system(size: 12, weight: .medium)).foregroundStyle(Color.vaultInk).padding(.horizontal, 14).padding(.vertical, 10).background(Color.vaultCard, in: Capsule()).overlay(Capsule().stroke(Color.vaultLine))
        }.accessibilityLabel("Switch vehicle")
    }
}

struct InfoLine: View {
    var title: String
    var value: String
    var body: some View {
        if !value.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    Text(title).foregroundStyle(.secondary).fixedSize()
                    Spacer()
                    Text(value).multilineTextAlignment(.trailing).textSelection(.enabled).fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).foregroundStyle(.secondary)
                    Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.font(.subheadline).padding(.vertical, 7)
        }
    }
}

struct VehicleRequired: View {
    @State private var adding = false
    var body: some View {
        EmptyVault(symbol: "car.side", title: "Your garage starts here", message: "Add a vehicle to organize its documents, parts and history.", actionTitle: "Add Vehicle", action: { adding = true })
            .sheet(isPresented: $adding) { NavigationStack { VehicleEditor() } }
    }
}

struct VaultErrorBanner: ViewModifier {
    @EnvironmentObject var store: VaultStore
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if let error = store.errorMessage ?? store.noticeMessage {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: store.errorMessage == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(store.errorMessage == nil ? Color.teal : .red)
                    Text(error).font(.caption).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                    Button { store.errorMessage = nil; store.noticeMessage = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Dismiss message")
                }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke((store.errorMessage == nil ? Color.teal : .red).opacity(0.2))).padding(12)
            }
        }
    }
}

extension View {
    func vaultErrorBanner() -> some View { modifier(VaultErrorBanner()) }
}
