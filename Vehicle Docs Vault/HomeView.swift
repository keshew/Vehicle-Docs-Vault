import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: VaultStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editor: RecordKind?
    @State private var addingVehicle = false
    @State private var editingVehicle = false
    @State private var promptedFirstVehicle = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                introduction
                if let vehicle = store.selectedVehicle {
                    HStack {
                        Text("SELECTED VEHICLE").font(.vaultEyebrow).tracking(1.8).foregroundStyle(.secondary)
                        Spacer(); VehicleMenu()
                    }
                    NavigationLink { VehicleDetail(vehicleID: vehicle.id) } label: { VehicleShowcaseCard(vehicle: vehicle) }.buttonStyle(.plain)
                        .contextMenu { Button("Edit Vehicle") { editingVehicle = true } }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 220 : 132), spacing: 12)], spacing: 12) {
                        ForEach([RecordKind.document, .replacement, .part, .note]) { kind in VaultActionTile(title: kind == .replacement ? "Replacement" : kind.title, symbol: kind.symbol) { editor = kind } }
                    }
                    overview(vehicle)
                    if sizeClass == .regular {
                        HStack(alignment: .top, spacing: 18) { DocumentStatusCard(vehicleID: vehicle.id); RecordActivityChart(vehicleID: vehicle.id) }
                    } else { DocumentStatusCard(vehicleID: vehicle.id); RecordActivityChart(vehicleID: vehicle.id) }
                    upcoming(vehicle)
                    MileageHistoryCard(vehicle: vehicle)
                    tireCard(vehicle)
                    recentSection(vehicle, kind: .replacement, title: "The service journal", subtitle: "A considered record of every change.")
                    recentSection(vehicle, kind: .note, title: "Worth remembering", subtitle: "The small details, kept close.")
                    NavigationLink { AttachmentsLibrary() } label: {
                        VaultCard {
                            HStack(spacing: 16) {
                                Image(systemName: "square.stack.3d.up").font(.system(size: 28, weight: .ultraLight)).foregroundStyle(Color.vaultGold)
                                VStack(alignment: .leading, spacing: 5) { Text("The file collection").font(.vaultDisplay(21)).foregroundStyle(Color.vaultInk); Text("Images, documents & receipts").font(.system(size: 11)).foregroundStyle(.secondary) }
                                Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 12)).foregroundStyle(Color.vaultGold)
                            }
                        }
                    }.buttonStyle(.plain)
                } else { firstVehicle }
                HStack(spacing: 8) { Rectangle().fill(Color.vaultLine).frame(height: 1); Image(systemName: "lock").font(.system(size: 9, weight: .light)); Text("PERSONAL. LOCAL. YOURS.").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.6); Rectangle().fill(Color.vaultLine).frame(height: 1) }.foregroundStyle(.secondary).padding(.vertical, 10)
            }.padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 24).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.background(Color.vaultBackground).navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 9) { Image(systemName: "square.stack.3d.up").font(.system(size: 18, weight: .light)).foregroundStyle(Color.vaultGold); Text("VEHICLE DOCS VAULT").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(Color.vaultInk) }
                }
                ToolbarItem(placement: .navigationBarTrailing) { NavigationLink { SearchView() } label: { Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .light)).foregroundStyle(Color.vaultInk) }.accessibilityLabel("Search all records") }
            }
            .sheet(item: $editor) { kind in if let vehicle = store.selectedVehicle { NavigationStack { RecordEditor(kind: kind, vehicleID: vehicle.id) } } }
            .sheet(isPresented: $addingVehicle) { NavigationStack { VehicleEditor() } }
            .sheet(isPresented: $editingVehicle) { if let vehicle = store.selectedVehicle { NavigationStack { VehicleEditor(vehicle: vehicle) } } }
            .onAppear {
                if !promptedFirstVehicle && store.database.vehicles.isEmpty { promptedFirstVehicle = true; addingVehicle = true }
            }
    }
    var introduction: some View {
        HStack(alignment: .top, spacing: 10) {
            VaultPageHeading(eyebrow: "The ownership collection", title: "Every detail.\nBeautifully kept.")
            Spacer(minLength: 0)
            NavigationLink { RecordsList(kind: .reminder) } label: {
                VaultIconButton(symbol: "bell").overlay(alignment: .topTrailing) {
                    if let id = store.selectedVehicle?.id, store.records(.reminder, vehicleID: id).contains(where: { !$0.completed }) { Circle().fill(Color.vaultGold).frame(width: 7, height: 7).overlay(Circle().stroke(Color.vaultBackground, lineWidth: 2)).offset(x: -4, y: 3) }
                }
            }.accessibilityLabel("Reminders").padding(.top, 21)
        }
    }
    var firstVehicle: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 0) {
                Text("A SPACE FOR YOUR VEHICLE").font(.vaultEyebrow).tracking(2).foregroundStyle(Color.vaultChampagne)
                Text("A remarkable car.\nAn impeccable record.").font(.vaultDisplay(31)).tracking(-0.8).foregroundStyle(.white).padding(.top, 18)
                AutomotiveSilhouette().frame(height: 175)
                Button { addingVehicle = true } label: { HStack { Text("Create your first vehicle"); Spacer(); Image(systemName: "arrow.right") }.font(.system(size: 12, weight: .medium)).foregroundStyle(Color.vaultNavy).padding(18).background(Color.vaultChampagne, in: RoundedRectangle(cornerRadius: 13)) }
            }.padding(25).background(Color.vaultNavy, in: RoundedRectangle(cornerRadius: 27))
            HStack(alignment: .top, spacing: 20) {
                welcomeFeature("01", title: "Documents", description: "Everything important, together.")
                welcomeFeature("02", title: "History", description: "Every change, remembered.")
                welcomeFeature("03", title: "Perspective", description: "Your records, at a glance.")
            }
        }
    }
    func welcomeFeature(_ index: String, title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(index).font(.vaultEyebrow).foregroundStyle(Color.vaultGold); Rectangle().fill(Color.vaultLine).frame(height: 1); Text(title).font(.vaultDisplay(17)).foregroundStyle(Color.vaultInk); Text(description).font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3) }.frame(maxWidth: .infinity, alignment: .leading)
    }
    func overview(_ vehicle: Vehicle) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 220 : 96), spacing: 10)], spacing: 10) {
            NavigationLink { RecordsList(kind: .document) } label: { VaultMetric(value: "\(store.records(.document, vehicleID: vehicle.id).count)", title: "Documents", symbol: "doc.text") }
            NavigationLink { RecordsList(kind: .part) } label: { VaultMetric(value: "\(store.records(.part, vehicleID: vehicle.id).filter { $0.status == "Installed" }.count)", title: "Installed parts", symbol: "gearshape.2") }
            NavigationLink { RecordsList(kind: .reminder) } label: { VaultMetric(value: "\(store.records(.reminder, vehicleID: vehicle.id).filter { !$0.completed }.count)", title: "Reminders", symbol: "bell") }
        }.buttonStyle(.plain)
    }
    func upcoming(_ vehicle: Vehicle) -> some View {
        let records = store.records(.document, vehicleID: vehicle.id).filter { $0.computedStatus == "Expired" || $0.computedStatus == "Expiring Soon" }.sorted { ($0.expiration ?? .distantFuture) < ($1.expiration ?? .distantFuture) }
        return VStack(alignment: .leading, spacing: 16) {
            HStack { VaultSectionHeading(title: "On the horizon", caption: "Dates that deserve your attention."); Spacer(); NavigationLink { ExpiringDocumentsView(vehicleID: vehicle.id) } label: { Image(systemName: "arrow.up.right").font(.system(size: 13)).foregroundStyle(Color.vaultGold) }.accessibilityLabel("View expiring documents") }
            if records.isEmpty {
                VaultCard {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "calendar.badge.checkmark").font(.system(size: 25, weight: .ultraLight)).foregroundStyle(Color.vaultGold)
                        VStack(alignment: .leading, spacing: 7) { Text(store.records(.document, vehicleID: vehicle.id).isEmpty ? "Make room for peace of mind." : "Nothing due in the next 30 days.").font(.system(size: 13, weight: .medium)); Text("Registration, insurance and important dates, carefully kept.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3); Button("Add Document") { editor = .document }.font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.vaultGold).padding(.top, 5) }
                    }
                }
            } else {
                ForEach(Array(records.prefix(3))) { record in NavigationLink { RecordDetail(recordID: record.id) } label: { ExpirationCard(record: record) }.buttonStyle(.plain) }
            }
        }
    }
    func recentSection(_ vehicle: Vehicle, kind: RecordKind, title: String, subtitle: String) -> some View {
        let records = Array(store.records(kind, vehicleID: vehicle.id).sorted { $0.date > $1.date }.prefix(2))
        return VStack(alignment: .leading, spacing: 15) {
            HStack { VaultSectionHeading(title: title, caption: subtitle); Spacer(); NavigationLink { RecordsList(kind: kind) } label: { Image(systemName: "arrow.up.right").font(.system(size: 13)).foregroundStyle(Color.vaultGold) }.accessibilityLabel("All \(kind.plural)") }
            VaultCard {
                if records.isEmpty {
                    VStack(alignment: .leading, spacing: 12) { Text(kind == .note ? "A home for details you want to keep." : "A complete history starts with one record.").font(.system(size: 12)).foregroundStyle(.secondary); Button { editor = kind } label: { Label("Add \(kind.title)", systemImage: "plus").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.vaultGold) } }
                } else {
                    VStack(spacing: 0) { ForEach(records) { record in NavigationLink { RecordDetail(recordID: record.id) } label: { VStack(alignment: .leading, spacing: 2) { RecordRow(record: record); if kind == .note { Text(record.notes).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4).lineLimit(2).padding(.bottom, 12) } } }.buttonStyle(.plain); if record.id != records.last?.id { Divider().overlay(Color.vaultLine) } } }
                }
            }
        }
    }
    func tireCard(_ vehicle: Vehicle) -> some View {
        let tire = store.records(.tire, vehicleID: vehicle.id).first { $0.status == "Installed" }
        return VStack(alignment: .leading, spacing: 16) {
            HStack { VaultSectionHeading(title: "Grounded in detail", caption: "Your current tire set."); Spacer(); NavigationLink { RecordsList(kind: .tire) } label: { Image(systemName: "arrow.up.right").font(.system(size: 13)).foregroundStyle(Color.vaultGold) }.accessibilityLabel("All tire sets") }
            VaultCard {
                HStack(spacing: 21) {
                    TireIllustration().frame(width: 75, height: 90)
                    VStack(alignment: .leading, spacing: 8) {
                        Text((tire?.category ?? "TIRE COLLECTION").uppercased()).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(Color.vaultGold)
                        Text(tire?.title ?? "Ready for every season.").font(.vaultDisplay(21)).foregroundStyle(Color.vaultInk)
                        if let tire { Text(tire.tireSize).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary); NavigationLink("View tire details") { RecordDetail(recordID: tire.id) }.font(.system(size: 10, weight: .medium)).foregroundStyle(Color.vaultGold) }
                        else { Button("Add Tire Set") { editor = .tire }.font(.system(size: 11, weight: .medium)).foregroundStyle(Color.vaultGold) }
                    }
                }
            }
        }
    }
}

struct ExpirationCard: View {
    @EnvironmentObject var store: VaultStore
    var record: VaultRecord
    var days: Int { Calendar.current.dateComponents([.day], from: Date().vaultDay, to: (record.expiration ?? Date()).vaultDay).day ?? 0 }
    var body: some View {
        HStack(spacing: 18) {
            VStack(spacing: 5) { Text("\(abs(days))").font(.system(.title, design: .rounded).weight(.light)).monospacedDigit(); Text(days < 0 ? (days == -1 ? "DAY LATE" : "DAYS LATE") : days == 0 ? "DUE TODAY" : (days == 1 ? "DAY LEFT" : "DAYS LEFT")).font(.system(.caption2, design: .monospaced).weight(.medium)).multilineTextAlignment(.center) }.foregroundStyle(days < 0 ? Color(red: 0.66, green: 0.28, blue: 0.26) : Color.vaultGold).frame(minWidth: 60)
            Rectangle().fill(Color.vaultLine).frame(width: 1, height: 42)
            VStack(alignment: .leading, spacing: 7) { Text(record.title).font(.subheadline.weight(.medium)).foregroundStyle(Color.vaultInk); Text(record.category + " · " + (record.expiration.map(store.date) ?? "")).font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 0); Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(19).background(Color.vaultCard, in: RoundedRectangle(cornerRadius: 19)).overlay(RoundedRectangle(cornerRadius: 19).stroke(Color.vaultLine))
            .accessibilityElement(children: .ignore).accessibilityLabel("\(record.title), \(record.category), \(store.expirationText(record))")
    }
}

struct TireIllustration: View {
    var body: some View {
        ZStack {
            Ellipse().fill(LinearGradient(colors: [Color(white: 0.18), Color(white: 0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 65, height: 86)
            ForEach(-4..<5, id: \.self) { index in Path { p in let y = CGFloat(index) * 8 + 45; p.move(to: CGPoint(x: 8, y: y - 6)); p.addLine(to: CGPoint(x: 26, y: y + 2)); p.addLine(to: CGPoint(x: 39, y: y - 3)) }.stroke(Color.white.opacity(0.10), lineWidth: 1) }.mask(Ellipse().frame(width: 65, height: 86))
            Ellipse().fill(Color(white: 0.13)).frame(width: 43, height: 73).overlay(Ellipse().stroke(Color.vaultChampagne.opacity(0.35), lineWidth: 1)).offset(x: 10)
            Ellipse().fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.20)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 31, height: 59).offset(x: 10)
            Ellipse().fill(Color(white: 0.10)).frame(width: 23, height: 49).offset(x: 10)
            ForEach(0..<5) { index in Capsule().fill(Color(white: 0.60)).frame(width: 2, height: 46).rotationEffect(.degrees(Double(index) * 36)).scaleEffect(x: 0.6, y: 1).offset(x: 10) }
        }.accessibilityHidden(true)
    }
}
