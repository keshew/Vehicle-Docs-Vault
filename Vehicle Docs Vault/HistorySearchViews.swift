import SwiftUI

struct SearchView: View {
    @EnvironmentObject var store: VaultStore
    @State private var query = ""
    @State private var loading = false
    @State private var vehicles: [Vehicle] = []
    @State private var records: [VaultRecord] = []
    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(Color.vaultBlue)
                        Text("Find a detail. In seconds.").font(.title2.weight(.bold))
                        Text("Search every vehicle, VIN, plate, document number, part, tire and note.").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 14)
                }
                if !store.database.recentSearches.isEmpty {
                    Section("Recent Searches") {
                        ForEach(store.database.recentSearches, id: \.self) { search in Button { query = search } label: { Label(search, systemImage: "clock") } }
                        Button("Clear Recent Searches") { store.commit { $0.recentSearches = [] } }.foregroundStyle(.secondary)
                    }
                }
            } else if loading { HStack { Spacer(); ProgressView("Searching your vault…"); Spacer() }.listRowBackground(Color.clear) }
            else {
                if vehicles.isEmpty && records.isEmpty { EmptyVault(symbol: "magnifyingglass", title: "No results", message: "Try a different name, VIN, number or phrase.") }
                if !vehicles.isEmpty {
                    Section("Vehicles") {
                        ForEach(vehicles) { vehicle in NavigationLink { VehicleDetail(vehicleID: vehicle.id) } label: { HStack(spacing: 14) { VehicleThumbnail(vehicle: vehicle, size: 48); VStack(alignment: .leading) { Text(vehicle.title).font(.headline); Text(vehicle.subtitle).font(.caption).foregroundStyle(.secondary) } } }.simultaneousGesture(TapGesture().onEnded { store.rememberSearch(query) }) }
                    }
                }
                ForEach(RecordKind.allCases) { kind in
                    let matches = records.filter { $0.kind == kind }
                    if !matches.isEmpty {
                        Section(kind.plural) {
                            ForEach(matches) { record in NavigationLink { RecordDetail(recordID: record.id) } label: { RecordRow(record: record, showVehicle: true) }.simultaneousGesture(TapGesture().onEnded { store.rememberSearch(query) }) }
                        }
                    }
                }
            }
        }.vaultListAppearance().navigationTitle("Search").searchable(text: $query, prompt: "Vehicles, VIN, documents, parts…")
            .onSubmit(of: .search) { store.rememberSearch(query) }
            .task(id: query) {
                loading = true
                await Task.yield()
                guard !Task.isCancelled else { return }
                refreshResults()
                loading = false
            }
            .onChange(of: store.revision) { _ in refreshResults() }
    }
    private func refreshResults() {
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { vehicles = []; records = [] }
                else {
                    vehicles = store.activeVehicles.filter { ([$0.name, $0.make, $0.model, $0.year, $0.plate] + Array($0.values.values)).joined(separator: " ").localizedCaseInsensitiveContains(trimmed) }
                    let active = Set(store.activeVehicles.map(\.id))
                    records = store.database.records.filter { !$0.archived && active.contains($0.vehicleID) && $0.searchable.localizedCaseInsensitiveContains(trimmed) }.sorted { $0.created > $1.created }
                }
    }
}

struct TimelineItem: Identifiable {
    var id: String
    var vehicleID: UUID
    var targetID: UUID
    var kind: RecordKind?
    var title: String
    var date: Date
}

struct TimelineView: View {
    @EnvironmentObject var store: VaultStore
    var vehicleID: UUID?
    var global = false
    @State private var filter = "All"
    var selectedID: UUID? { global ? nil : (vehicleID ?? store.selectedVehicle?.id) }
    var items: [TimelineItem] {
        let active = Set(store.activeVehicles.map(\.id))
        var result = store.database.events.filter { (selectedID == nil || $0.vehicleID == selectedID) && (global || vehicleID != nil || active.contains($0.vehicleID)) }.map {
            TimelineItem(id: $0.id.uuidString, vehicleID: $0.vehicleID, targetID: $0.targetID, kind: $0.kind, title: $0.title, date: $0.date)
        }
        for record in store.database.records where record.kind == .document && !record.archived && (selectedID == nil || record.vehicleID == selectedID) && (global || vehicleID != nil || active.contains(record.vehicleID)) {
            if let expiration = record.expiration, let expiredOn = Calendar.current.date(byAdding: .day, value: 1, to: expiration.vaultDay), expiredOn <= Date() {
                result.append(TimelineItem(id: record.id.uuidString + "-expired", vehicleID: record.vehicleID, targetID: record.id, kind: .document, title: "\(record.title) · expired", date: expiredOn))
            }
        }
        return result.filter { filter == "All" || group($0.kind) == filter }.sorted { $0.date > $1.date }
    }
    var months: [Date] {
        Array(Set(items.map { Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: $0.date)) ?? $0.date.vaultDay })).sorted(by: >)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VaultPageHeading(eyebrow: global ? "The complete collection" : "The ownership journal", title: "A story in the details.", subtitle: "Every addition. Every change. In order.")
                if !global && selectedID == nil { VehicleRequired() }
                else {
                    if !global && vehicleID == nil { VehicleMenu() }
                    RecordActivityChart(vehicleID: selectedID)
                    ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { ForEach(["All", "Documents", "Parts", "Tires", "Notes", "Reminders"], id: \.self) { value in VaultChip(title: value, selected: filter == value) { filter = value } } }.padding(.vertical, 1) }
                    if !global {
                        NavigationLink { TimelineView(global: true) } label: { HStack { Image(systemName: "square.stack.3d.up").foregroundStyle(Color.vaultGold); Text("Activity across all vehicles").foregroundStyle(Color.vaultInk); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(Color.vaultGold) }.font(.system(size: 11)).padding(18).background(Color.vaultCard, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.vaultLine)) }.buttonStyle(.plain)
                    }
                    if items.isEmpty { EmptyVault(symbol: "clock.arrow.circlepath", title: "A history worth keeping.", message: "Every record you add becomes a part of your vehicle's story.") }
                    LazyVStack(alignment: .leading, spacing: 25) {
                        ForEach(months, id: \.self) { month in
                            VStack(alignment: .leading, spacing: 17) {
                                HStack { Text(month.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "en_US")))).font(.vaultDisplay(23)).foregroundStyle(Color.vaultInk); Spacer(); Rectangle().fill(Color.vaultLine).frame(width: 35, height: 1) }
                                let entries = items.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
                                VStack(spacing: 0) {
                                    ForEach(entries) { item in
                                        HStack(alignment: .top, spacing: 15) {
                                            VStack(spacing: 8) { Circle().fill(item.kind?.tint ?? .vaultGold).frame(width: 6, height: 6).padding(4).background(Circle().stroke(Color.vaultLine)); Rectangle().fill(Color.vaultLine).frame(width: 1).frame(minHeight: 65) }.frame(width: 14).padding(.top, 16).accessibilityHidden(true)
                                            NavigationLink { destination(item) } label: {
                                                VStack(alignment: .leading, spacing: 14) {
                                                    HStack { Text(item.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "en_US")))).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Color.vaultGold); Spacer(); Text(item.date.vaultTime).font(.system(size: 9)).foregroundStyle(.secondary) }
                                                    HStack(alignment: .top, spacing: 13) { Image(systemName: item.kind?.symbol ?? "car.side").font(.system(size: 22, weight: .ultraLight)).foregroundStyle(Color.vaultGold).frame(width: 25); VStack(alignment: .leading, spacing: 7) { Text(item.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.vaultInk).multilineTextAlignment(.leading); if global { Text(store.vehicle(item.vehicleID)?.title ?? "Vehicle").font(.system(size: 10)).foregroundStyle(.secondary) } }; Spacer(minLength: 0); Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(.secondary) }
                                                }.padding(19).frame(maxWidth: .infinity, alignment: .leading).background(Color.vaultCard, in: RoundedRectangle(cornerRadius: 19)).overlay(RoundedRectangle(cornerRadius: 19).stroke(Color.vaultLine))
                                            }.buttonStyle(.plain).padding(.bottom, 13)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }.padding(22).frame(maxWidth: 850).frame(maxWidth: .infinity)
        }.background(Color.vaultBackground).navigationTitle(global ? "Activity History" : "Timeline").navigationBarTitleDisplayMode(.inline)
            .toolbar { NavigationLink { SearchView() } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Search") }
    }
    func group(_ kind: RecordKind?) -> String {
        switch kind {
        case .document: return "Documents"
        case .part, .replacement: return "Parts"
        case .tire, .tireChange: return "Tires"
        case .note: return "Notes"
        case .reminder: return "Reminders"
        default: return "Vehicles"
        }
    }
    @ViewBuilder func destination(_ item: TimelineItem) -> some View {
        if item.kind != nil { RecordDetail(recordID: item.targetID) }
        else { VehicleDetail(vehicleID: item.vehicleID) }
    }
}
