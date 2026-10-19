import SwiftUI
import UIKit

extension Font {
    static func vaultDisplay(_ size: CGFloat) -> Font { .custom("Georgia", size: size, relativeTo: size >= 30 ? .largeTitle : .title2) }
    static let vaultEyebrow = Font.system(.caption2, design: .monospaced).weight(.semibold)
}

struct VaultPageHeading: View {
    var eyebrow: String
    var title: String
    var subtitle: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(eyebrow.uppercased()).font(.vaultEyebrow).tracking(2.4).foregroundStyle(Color.vaultGold)
            Text(title).font(.vaultDisplay(38)).tracking(-1.4).foregroundStyle(Color.vaultInk).fixedSize(horizontal: false, vertical: true)
            if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineSpacing(4) }
        }
    }
}

struct VaultSectionHeading: View {
    var title: String
    var caption: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(.title2, design: .serif)).foregroundStyle(Color.vaultInk)
            if !caption.isEmpty { Text(caption).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct VaultIconButton: View {
    var symbol: String
    var body: some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(Color.vaultInk)
            .frame(width: 46, height: 46).background(Color.vaultCard, in: Circle())
            .overlay(Circle().stroke(Color.vaultLine, lineWidth: 1))
    }
}

struct VaultChip: View {
    var title: String
    var selected = false
    var count: Int?
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title).font(.subheadline.weight(.medium))
                if let count { Text("\(count)").font(.system(.caption, design: .monospaced).weight(.semibold)).opacity(0.6) }
            }.padding(.horizontal, 16).padding(.vertical, 11).frame(minHeight: 44)
                .foregroundStyle(selected ? Color.vaultCanvasText : Color.vaultInk)
                .background(selected ? Color.vaultInk : Color.vaultCard, in: Capsule())
                .overlay(Capsule().stroke(selected ? Color.clear : Color.vaultLine, lineWidth: 1))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct VaultActionTile: View {
    var title: String
    var symbol: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 21, weight: .light)).foregroundStyle(Color.vaultGold)
                    Spacer(minLength: 1)
                    Image(systemName: "plus").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                }
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Color.vaultInk).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.vaultCard, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.vaultLine, lineWidth: 1))
        }.buttonStyle(.plain).accessibilityLabel("Add \(title)")
    }
}

struct VaultMetric: View {
    var value: String
    var title: String
    var symbol: String
    var accent: Color = .vaultGold
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Image(systemName: symbol).font(.system(size: 16, weight: .light)).foregroundStyle(accent); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(.tertiary) }
            VStack(alignment: .leading, spacing: 5) { Text(value).font(.system(.largeTitle, design: .rounded).weight(.light)).monospacedDigit().foregroundStyle(Color.vaultInk); Text(title).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.vaultCard, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.vaultLine))
    }
}

struct VaultListAppearance: ViewModifier {
    func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden).scrollDismissesKeyboard(.interactively).background(Color.vaultBackground)
            .environment(\.defaultMinListRowHeight, 54)
            .listStyle(.insetGrouped)
    }
}

extension View {
    func vaultListAppearance() -> some View { modifier(VaultListAppearance()) }
    func vaultEditorSafety(hasChanges: Bool, isBusy: Bool, confirmDiscard: Binding<Bool>) -> some View {
        modifier(VaultEditorSafety(hasChanges: hasChanges, isBusy: isBusy, confirmDiscard: confirmDiscard))
    }
}

private struct VaultEditorSafety: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    var hasChanges: Bool
    var isBusy: Bool
    @Binding var confirmDiscard: Bool

    func body(content: Content) -> some View {
        content.interactiveDismissDisabled(hasChanges || isBusy)
            .confirmationDialog("Discard unsaved changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { }
            } message: { Text("Your changes and newly selected attachments have not been saved.") }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
    }
}

@MainActor
enum VaultAppearance {
    static func configure() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithTransparentBackground()
        navigation.backgroundColor = UIColor(Color.vaultBackground)
        navigation.shadowColor = .clear
        navigation.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: UIColor(Color.vaultInk)]
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle).withDesign(.serif) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle)
        navigation.largeTitleTextAttributes = [.font: UIFont(descriptor: descriptor, size: 36), .foregroundColor: UIColor(Color.vaultInk)]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UITableView.appearance().backgroundColor = UIColor(Color.vaultBackground)
        UITableViewCell.appearance().backgroundColor = UIColor(Color.vaultCard)
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Color.vaultCard)
        tab.shadowColor = UIColor(Color.vaultLine)
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = .secondaryLabel
            item.normal.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: UIColor.secondaryLabel]
            item.selected.iconColor = UIColor(Color.vaultGold)
            item.selected.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: UIColor(Color.vaultGold)]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

struct VaultSearchField: View {
    @Binding var text: String
    var placeholder: String
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .light)).foregroundStyle(Color.vaultGold)
            TextField(placeholder, text: $text).font(.subheadline).autocorrectionDisabled().submitLabel(.search).focused($focused).onSubmit { focused = false }
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill").font(.subheadline).foregroundStyle(.secondary).frame(minWidth: 32, minHeight: 32) }.accessibilityLabel("Clear search") }
        }.padding(.horizontal, 17).padding(.vertical, 15).background(Color.vaultCard, in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.vaultLine))
    }
}

struct PremiumRecordCard: View {
    @EnvironmentObject var store: VaultStore
    var record: VaultRecord
    var showVehicle = false
    var body: some View {
        if record.kind == .document { DocumentPassCard(record: record, showVehicle: showVehicle) }
        else {
            VStack(alignment: .leading, spacing: 10) {
                if showVehicle { Text((store.vehicle(record.vehicleID)?.title ?? "Vehicle").uppercased()).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(Color.vaultGold) }
                if record.kind == .tire {
                    HStack(spacing: 20) { TireIllustration().frame(width: 66, height: 90); VStack(alignment: .leading, spacing: 8) { Text(record.category.uppercased()).font(.vaultEyebrow).tracking(1.6).foregroundStyle(Color.vaultGold); Text(record.title).font(.vaultDisplay(23)).foregroundStyle(Color.vaultInk); Text(record.tireSize).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary); StatusPill(value: record.computedStatus) } }
                } else { RecordRow(record: record) }
                if record.kind == .note { Text(record.notes).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4).lineLimit(3) }
                if record.kind == .part && !record["location"].isEmpty { HStack(spacing: 6) { Image(systemName: "shippingbox"); Text(record["location"]) }.font(.system(size: 10)).foregroundStyle(.secondary) }
                if record.kind == .tire, let date = ISO8601DateFormatter().date(from: record["installedDate"]) {
                    Divider().padding(.vertical, 5)
                    HStack { Text("Installed \(store.date(date))"); Spacer(); if !record["mileage"].isEmpty { Text("\(record["mileage"]) \(record["distanceUnit"].isEmpty ? store.distanceSuffix : record["distanceUnit"])") } }.font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color.vaultCard, in: RoundedRectangle(cornerRadius: 21)).overlay(RoundedRectangle(cornerRadius: 21).stroke(Color.vaultLine))
        }
    }
}

struct DocumentPassCard: View {
    @EnvironmentObject var store: VaultStore
    var record: VaultRecord
    var showVehicle = false
    var color: Color { record.computedStatus == "Expired" ? Color(red: 0.66, green: 0.28, blue: 0.26) : .vaultGold }
    var elapsed: Double {
        guard let expiration = record.expiration, expiration > record.date else { return 0 }
        return min(1, max(0, Date().timeIntervalSince(record.date) / expiration.timeIntervalSince(record.date)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                HStack(spacing: 8) { Image(systemName: "doc.text").font(.system(size: 14, weight: .light)); Text(record.category.uppercased()).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.7) }.foregroundStyle(color)
                Spacer(); StatusPill(value: record.computedStatus)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(record.title).font(.vaultDisplay(25)).tracking(-0.6).foregroundStyle(Color.vaultInk).multilineTextAlignment(.leading)
                if showVehicle { Text(store.vehicle(record.vehicleID)?.title ?? "Vehicle").font(.system(size: 11)).foregroundStyle(.secondary) }
                if !record["number"].isEmpty { Text(record["number"]).font(.system(size: 10, weight: .regular, design: .monospaced)).tracking(1.2).foregroundStyle(.secondary).lineLimit(1) }
            }
            Rectangle().fill(Color.vaultLine).frame(height: 1)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) { Text(record.expiration == nil ? "VALIDITY" : "EXPIRES").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(.secondary); Text(record.expiration.map(store.date) ?? "No expiration date").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.vaultInk) }
                Spacer()
                HStack(spacing: 6) { Image(systemName: "paperclip"); Text("\(store.attachments(for: record.id).count)") }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 12)
                Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(color).padding(.leading, 14).padding(.top, 12)
            }
            if record.expiration != nil {
                GeometryReader { geometry in
                    Capsule().fill(color.opacity(0.09)).overlay(alignment: .leading) { Capsule().fill(color.opacity(0.7)).frame(width: geometry.size.width * elapsed) }
                }.frame(height: 3).accessibilityLabel("Validity period elapsed: \(Int(elapsed * 100)) percent")
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Color.vaultCard, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.vaultLine))
    }
}

struct VaultEditorHeading: View {
    var title: String
    var subtitle: String
    var symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack { Text("CURATE YOUR ARCHIVE").font(.vaultEyebrow).tracking(1.6).foregroundStyle(Color.vaultGold); Spacer(); Image(systemName: symbol).font(.system(size: 22, weight: .ultraLight)).foregroundStyle(Color.vaultGold) }
            Text(title).font(.vaultDisplay(29)).tracking(-0.7).foregroundStyle(Color.vaultInk)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
        }.padding(.vertical, 15).frame(maxWidth: .infinity, alignment: .leading)
    }
}
