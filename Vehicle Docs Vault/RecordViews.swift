import SwiftUI

struct RecordsList: View {
    @EnvironmentObject var store: VaultStore
    var kind: RecordKind
    var vehicleID: UUID?
    @State private var status: String
    @State private var category: String
    @State private var search = ""
    @State private var sort = "Recently Added"
    @State private var dateFilter = false
    @State private var dateFrom = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var dateTo = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var adding = false
    init(kind: RecordKind, vehicleID: UUID? = nil, initialStatus: String = "All", initialCategory: String = "All") {
        self.kind = kind; self.vehicleID = vehicleID
        _status = State(initialValue: initialStatus)
        _category = State(initialValue: initialCategory)
        _sort = State(initialValue: kind == .document ? "Expiration Date" : "Date")
    }
    var selectedID: UUID? { vehicleID ?? store.selectedVehicle?.id }
    var hasFilters: Bool { !search.isEmpty || status != "All" || category != "All" || dateFilter }
    var filtered: [VaultRecord] {
        guard let selectedID else { return [] }
        return store.records(kind, vehicleID: selectedID, includeArchived: status == "Archived").filter { record in
            let date = kind == .document ? record.expiration : record.date
            return (status == "All" ? !record.archived : record.computedStatus == status)
                && (category == "All" || record.category == category)
                && (search.isEmpty || record.searchable.localizedCaseInsensitiveContains(search))
                && (!dateFilter || (date != nil && date!.vaultDay >= dateFrom.vaultDay && date!.vaultDay <= dateTo.vaultDay))
        }.sorted {
            switch sort {
            case "Name": return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            case "Expiration Date": return ($0.expiration ?? .distantFuture) < ($1.expiration ?? .distantFuture)
            case "Date": return kind == .reminder ? $0.date < $1.date : $0.date > $1.date
            default: return $0.created > $1.created
            }
        }
    }
    var statuses: [String] {
        switch kind {
        case .document: return ["All", "Active", "Expiring Soon", "Expired", "No Expiration", "Archived"]
        case .part: return ["All", "Installed", "Stored", "Removed", "Archived"]
        case .tire: return ["All", "Installed", "Stored", "Retired", "Archived"]
        case .reminder: return ["All", "Upcoming", "Completed", "Past"]
        default: return ["All", "Archived"]
        }
    }
    @State private var showingFilters = false
    var screenTitle: String { kind == .replacement ? "The service journal." : kind == .tireChange ? "Season to season." : kind == .document ? "The document vault." : kind == .tire ? "The tire collection." : kind == .note ? "The finer details." : kind == .reminder ? "Always on your radar." : "The parts collection." }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VaultPageHeading(eyebrow: kind.plural, title: screenTitle)
                if selectedID == nil { VehicleRequired() }
                else {
                    if vehicleID == nil { VehicleMenu() }
                    VaultSearchField(text: $search, placeholder: "Search \(kind.plural.lowercased())")
                    if kind == .document, let selectedID { DocumentStatusCard(vehicleID: selectedID, compact: true) }
                    HStack {
                        Text("\(filtered.count) RECORD\(filtered.count == 1 ? "" : "S")").font(.vaultEyebrow).tracking(1.5).foregroundStyle(.secondary)
                        Spacer()
                        Button { showingFilters = true } label: { Label("Refine", systemImage: "slider.horizontal.3").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.vaultGold) }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { ForEach(statuses, id: \.self) { value in VaultChip(title: value, selected: status == value) { status = value } } }.padding(.vertical, 1)
                    }
                    if kind == .document {
                        HStack(spacing: 12) {
                            NavigationLink { CategoriesView(kind: kind, vehicleID: selectedID) } label: { shortcut("Categories", "square.grid.2x2") }
                            NavigationLink { ExpiringDocumentsView(vehicleID: selectedID) } label: { shortcut("Upcoming dates", "calendar") }
                        }.buttonStyle(.plain)
                    }
                    if filtered.isEmpty {
                        EmptyVault(symbol: kind.symbol, title: hasFilters ? "No matching records" : kind.emptyTitle,
                                   message: hasFilters ? "Try a different search or clear your filters to see the rest of this collection." : "Keep the details and attachments for each \(kind.title.lowercased()) together.",
                                   actionTitle: hasFilters ? "Clear Filters" : "Add \(kind.title)", action: { if hasFilters { clearFilters() } else { adding = true } })
                    } else { recordSections }
                }
            }.padding(22).frame(maxWidth: 850).frame(maxWidth: .infinity)
        }.background(Color.vaultBackground).navigationTitle(kind.plural).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItemGroup(placement: .navigationBarTrailing) {
                NavigationLink { SearchView() } label: { Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .light)) }.accessibilityLabel("Global search")
                Button { adding = true } label: { Image(systemName: "plus").font(.system(size: 15, weight: .medium)).foregroundStyle(Color.vaultGold) }.disabled(selectedID == nil).accessibilityLabel("Add \(kind.title)")
            } }
            .sheet(isPresented: $adding) { if let selectedID { NavigationStack { RecordEditor(kind: kind, vehicleID: selectedID) } } }
            .sheet(isPresented: $showingFilters) { filterSheet }
    }
    func shortcut(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 9) { Image(systemName: symbol).foregroundStyle(Color.vaultGold); Text(title).foregroundStyle(Color.vaultInk); Spacer(minLength: 0); Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(.secondary) }.font(.system(size: 11)).padding(15).background(Color.vaultCard, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.vaultLine))
    }
    var filterSheet: some View {
        NavigationStack {
            Form {
                Picker("Status", selection: $status) { ForEach(statuses, id: \.self) { Text($0) } }
                if !kind.categories.isEmpty { Picker(kind == .tire ? "Season" : "Category", selection: $category) { Text("All").tag("All"); ForEach(kind.categories, id: \.self) { Text($0) } } }
                Picker("Sort", selection: $sort) { ForEach(kind == .document ? ["Expiration Date", "Name", "Recently Added"] : ["Date", "Name", "Recently Added"], id: \.self) { Text($0) } }
                Toggle(kind == .document ? "Filter Expiration Dates" : "Filter Dates", isOn: $dateFilter)
                if dateFilter { DatePicker("From", selection: $dateFrom, displayedComponents: .date).onChange(of: dateFrom) { value in if dateTo < value { dateTo = value } }; DatePicker("To", selection: $dateTo, in: dateFrom..., displayedComponents: .date) }
                Button("Clear Filters", action: clearFilters)
            }.vaultListAppearance().navigationTitle("Refine collection").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingFilters = false } } }
        }.presentationDetents([.medium, .large])
    }
    func clearFilters() { category = "All"; status = "All"; dateFilter = false; search = "" }
    @ViewBuilder var recordSections: some View {
        if [.document, .part, .tire, .reminder].contains(kind) {
            ForEach(statuses.filter { $0 != "All" }, id: \.self) { group in
                let records = filtered.filter { $0.computedStatus == group }
                if !records.isEmpty {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack { Text(group == "Installed" && kind == .tire ? "Current set" : group == "Retired" ? "Previous sets" : group).font(.vaultDisplay(21)); Spacer(); Text(String(format: "%02d", records.count)).font(.vaultEyebrow).foregroundStyle(.secondary) }
                        ForEach(records) { row($0) }
                    }
                }
            }
        } else { LazyVStack(spacing: 14) { ForEach(filtered) { row($0) } } }
    }
    func row(_ record: VaultRecord) -> some View {
        NavigationLink { RecordDetail(recordID: record.id) } label: { PremiumRecordCard(record: record) }.buttonStyle(.plain)
            .contextMenu { Button(record.archived ? "Restore Record" : "Archive Record") { store.setArchived(record: record, archived: !record.archived) } }
    }
}

struct PartsHub: View {
    @EnvironmentObject var store: VaultStore
    @State private var adding = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                VaultPageHeading(eyebrow: "Parts & equipment", title: "The workshop.", subtitle: "An exact record of what makes it yours.")
                if let vehicle = store.selectedVehicle {
                    VehicleMenu()
                    HStack(spacing: 11) {
                        NavigationLink { RecordsList(kind: .part, initialStatus: "Installed") } label: { VaultMetric(value: "\(store.records(.part, vehicleID: vehicle.id).filter { $0.status == "Installed" }.count)", title: "Installed parts", symbol: "gearshape.2") }
                        NavigationLink { RecordsList(kind: .part, initialStatus: "Stored") } label: { VaultMetric(value: "\(store.records(.part, vehicleID: vehicle.id).filter { $0.status == "Stored" }.count)", title: "In storage", symbol: "shippingbox") }
                    }.buttonStyle(.plain)
                    RecordActivityChart(vehicleID: vehicle.id, replacementsOnly: true)
                    HStack { VaultSectionHeading(title: "The inventory"); Spacer(); Button { adding = true } label: { Label("Add part", systemImage: "plus").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.vaultGold) } }
                    VStack(spacing: 12) {
                        destination("All parts", subtitle: "Specifications, quantities & locations", symbol: "gearshape.2") { RecordsList(kind: .part) }
                        destination("By category", subtitle: "A place for every component", symbol: "square.grid.2x2") { CategoriesView(kind: .part, vehicleID: vehicle.id) }
                        destination("Replacement history", subtitle: "Every change, in chronological order", symbol: "wrench.and.screwdriver") { RecordsList(kind: .replacement) }
                    }
                    NavigationLink { RecordsList(kind: .tire) } label: {
                        HStack(spacing: 23) {
                            TireIllustration().frame(width: 78, height: 100)
                            VStack(alignment: .leading, spacing: 9) { Text("THE TIRE COLLECTION").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.7).foregroundStyle(Color.vaultChampagne); Text("For every season.").font(.vaultDisplay(27)).foregroundStyle(.white); Text("\(store.records(.tire, vehicleID: vehicle.id).count) sets in your collection").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)); Image(systemName: "arrow.right").font(.system(size: 14, weight: .light)).foregroundStyle(Color.vaultChampagne) }
                            Spacer(minLength: 0)
                        }.padding(25).frame(maxWidth: .infinity, alignment: .leading).background(Color.vaultNavy, in: RoundedRectangle(cornerRadius: 25))
                    }.buttonStyle(.plain)
                    destination("Tire changes", subtitle: "Installation dates & mileage", symbol: "arrow.triangle.2.circlepath") { RecordsList(kind: .tireChange) }
                    VaultSectionHeading(title: "Recent replacements")
                    let recent = Array(store.records(.replacement, vehicleID: vehicle.id).sorted { $0.date > $1.date }.prefix(3))
                    if recent.isEmpty { EmptyVault(symbol: "wrench.and.screwdriver", title: "The beginning of a better record.", message: "Keep a history of the parts you replace.", actionTitle: "Add Replacement", action: { addingReplacement = true }) }
                    ForEach(recent) { record in NavigationLink { RecordDetail(recordID: record.id) } label: { PremiumRecordCard(record: record) }.buttonStyle(.plain) }
                } else { VehicleRequired() }
            }.padding(22).frame(maxWidth: 850).frame(maxWidth: .infinity)
        }.background(Color.vaultBackground).navigationTitle("Parts").navigationBarTitleDisplayMode(.inline)
            .toolbar { NavigationLink { SearchView() } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Search") }
            .sheet(isPresented: $adding) { if let vehicle = store.selectedVehicle { NavigationStack { RecordEditor(kind: .part, vehicleID: vehicle.id) } } }
            .sheet(isPresented: $addingReplacement) { if let vehicle = store.selectedVehicle { NavigationStack { RecordEditor(kind: .replacement, vehicleID: vehicle.id) } } }
    }
    @State private var addingReplacement = false
    func destination<Destination: View>(_ title: String, subtitle: String, symbol: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 16) { Image(systemName: symbol).font(.system(size: 22, weight: .ultraLight)).foregroundStyle(Color.vaultGold).frame(width: 35); VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.vaultInk); Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(Color.vaultGold) }.padding(20).background(Color.vaultCard, in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.vaultLine))
        }.buttonStyle(.plain)
    }
}

struct CategoriesView: View {
    @EnvironmentObject var store: VaultStore
    var kind: RecordKind
    var vehicleID: UUID?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                VaultPageHeading(eyebrow: "Curated & categorized", title: "Everything in its place.")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(kind.categories, id: \.self) { category in
                        NavigationLink { RecordsList(kind: kind, vehicleID: vehicleID, initialCategory: category) } label: {
                            VStack(alignment: .leading, spacing: 23) {
                                HStack { Image(systemName: symbol(category)).font(.system(size: 25, weight: .ultraLight)).foregroundStyle(Color.vaultGold); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(.secondary) }
                                VStack(alignment: .leading, spacing: 8) { Text("\(store.records(kind, vehicleID: vehicleID).filter { $0.category == category }.count)").font(.system(size: 30, weight: .light, design: .rounded)); Text(category).font(.vaultDisplay(18)) }.foregroundStyle(Color.vaultInk)
                            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color.vaultCard, in: RoundedRectangle(cornerRadius: 21)).overlay(RoundedRectangle(cornerRadius: 21).stroke(Color.vaultLine))
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(22).frame(maxWidth: 850).frame(maxWidth: .infinity)
        }.background(Color.vaultBackground).navigationTitle("\(kind.title) Categories").navigationBarTitleDisplayMode(.inline)
    }
    func symbol(_ category: String) -> String {
        ["Registration": "doc.text", "Insurance": "shield.lefthalf.filled", "Inspection": "checkmark.seal", "Ownership": "key", "Tax": "building.columns", "Warranty": "checkmark.shield", "Engine": "engine.combustion", "Filters": "line.3.horizontal.decrease", "Brakes": "circle.circle", "Battery": "battery.100", "Lights": "lightbulb", "Tires": "circle.circle", "Fluids": "drop", "Electrical": "bolt", "Interior": "car.side", "Exterior": "car.side", "Suspension": "arrow.up.and.down"][category] ?? "square.stack"
    }
}

struct ExpiringDocumentsView: View {
    @EnvironmentObject var store: VaultStore
    var vehicleID: UUID?
    @State private var adding = false
    var records: [VaultRecord] {
        let active = Set(store.activeVehicles.map(\.id))
        return store.records(.document, vehicleID: vehicleID).filter { $0.expiration != nil && $0.expiration!.vaultDay >= Date().vaultDay && active.contains($0.vehicleID) }.sorted { $0.expiration! < $1.expiration! }
    }
    var body: some View {
        List {
            if records.isEmpty { EmptyVault(symbol: "calendar.badge.checkmark", title: "No upcoming expirations", message: "Documents with expiration dates will be grouped here.", actionTitle: "Add Document", action: { adding = true }) }
            ForEach(["Next 7 Days", "Next 30 Days", "Later"], id: \.self) { group in
                let items = records.filter { bucket($0) == group }
                if !items.isEmpty {
                    Section(group) {
                        ForEach(items) { record in
                            NavigationLink { RecordDetail(recordID: record.id) } label: { ExpirationCard(record: record) }.buttonStyle(.plain).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                        }
                    }
                }
            }
        }.vaultListAppearance().navigationTitle("Expiring Documents").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $adding) { if let id = vehicleID ?? store.selectedVehicle?.id { NavigationStack { RecordEditor(kind: .document, vehicleID: id) } } }
    }
    func bucket(_ record: VaultRecord) -> String {
        let days = Calendar.current.dateComponents([.day], from: Date().vaultDay, to: record.expiration!.vaultDay).day ?? 0
        return days <= 7 ? "Next 7 Days" : days <= 30 ? "Next 30 Days" : "Later"
    }
}

struct RecordDetail: View {
    @EnvironmentObject var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    var recordID: UUID
    @State private var editing = false
    @State private var deleting = false
    @State private var replacement: VaultRecord?
    @State private var tireChange: VaultRecord?
    var record: VaultRecord? { store.record(recordID) }
    var body: some View {
        Group {
            if let record {
                List {
                    Section {
                        if record.kind == .document { DocumentPassCard(record: record, showVehicle: true).listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                        else {
                            VStack(alignment: .leading, spacing: 18) {
                                Image(systemName: record.kind.symbol).font(.system(size: 27, weight: .ultraLight)).foregroundStyle(Color.vaultChampagne)
                                Text(record.title).font(.vaultDisplay(31)).tracking(-0.7).foregroundStyle(.white).textSelection(.enabled)
                                HStack { Text(record.category.uppercased()).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.6).foregroundStyle(Color.vaultChampagne); Spacer(); StatusPill(value: record.computedStatus) }
                            }.padding(25).frame(maxWidth: .infinity, alignment: .leading).background(Color.vaultNavy, in: RoundedRectangle(cornerRadius: 24)).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                        }
                    }
                    Section("Related Vehicle") {
                        if let vehicle = store.vehicle(record.vehicleID) { NavigationLink { VehicleDetail(vehicleID: vehicle.id) } label: { HStack { VehicleThumbnail(vehicle: vehicle, size: 42); Text(vehicle.title).font(.subheadline.weight(.medium)) } } }
                    }
                    detailSections(record)
                    if !record.notes.isEmpty { Section(record.kind == .note ? "Note" : "Notes") { Text(record.notes).font(.body).textSelection(.enabled).padding(.vertical, 5) } }
                    Section("Attachments") { AttachmentLinks(ownerID: record.id) }
                    relatedRecords(record)
                    Section("Actions") {
                        if !record.archived && store.vehicle(record.vehicleID)?.archived == false { actions(record) }
                        Button(record.archived ? "Restore Record" : "Archive Record") { store.setArchived(record: record, archived: !record.archived) }
                        Button("Delete \(record.kind.title)", role: .destructive) { deleting = true }
                    }
                }
            } else { EmptyVault(symbol: "doc.questionmark", title: "Record unavailable", message: "This record may have been removed.") }
        }.vaultListAppearance().navigationTitle(record?.kind.title ?? "Record").navigationBarTitleDisplayMode(.inline)
            .toolbar { if record != nil { Button("Edit") { editing = true } } }
            .sheet(isPresented: $editing) { if let record { NavigationStack { RecordEditor(kind: record.kind, vehicleID: record.vehicleID, record: record) } } }
            .sheet(item: $replacement) { draft in
                NavigationStack { RecordEditor(kind: .document, vehicleID: draft.vehicleID, record: draft, creating: true, replacingDocumentID: recordID) }
            }
            .sheet(item: $tireChange) { change in NavigationStack { RecordEditor(kind: .tireChange, vehicleID: change.vehicleID, record: change, creating: true) } }
            .confirmationDialog("Delete this record and its attachments? This cannot be undone.", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete Record", role: .destructive) { if store.deleteRecord(recordID) { dismiss() } }
            }
    }
    @ViewBuilder func detailSections(_ record: VaultRecord) -> some View {
        switch record.kind {
        case .document:
            Section("Document Information") {
                InfoLine(title: "Document Number", value: record["number"])
                InfoLine(title: "Issuing Organization", value: record["issuer"])
                InfoLine(title: "Issue Date", value: store.date(record.date))
                InfoLine(title: "Expiration Date", value: record.expiration.map(store.date) ?? "No expiration")
            }
        case .part:
            Section("Part Information") {
                detailFields(record, keys: [("Manufacturer", "manufacturer"), ("Part Number", "partNumber"), ("Model", "model"), ("Quantity", "quantity"), ("Storage Location", "location")])
                installationInfo(record)
            }
        case .replacement, .tireChange:
            Section("Record Information") {
                InfoLine(title: "Date", value: store.date(record.date))
                mileageInfo(record)
                linkedRecord("Removed", id: record["removedID"], historicalName: record["removedName"])
                linkedRecord("Installed", id: record["installedID"], historicalName: record["installedName"])
            }
        case .tire:
            Section("Tire Specification") {
                detailFields(record, keys: [("Manufacturer", "manufacturer"), ("Model", "model"), ("Production Year", "productionYear"), ("Storage Location", "location")])
                InfoLine(title: "Size", value: record.tireSize)
                InfoLine(title: "Season", value: record.category)
                if let date = ISO8601DateFormatter().date(from: record["purchaseDate"]) { InfoLine(title: "Purchased", value: store.date(date)) }
                installationInfo(record)
            }
        case .note:
            Section("Record Information") { InfoLine(title: "Date", value: store.date(record.date)); InfoLine(title: "Category", value: record.category) }
        case .reminder:
            Section("Schedule") {
                InfoLine(title: "Date", value: store.date(record.date))
                InfoLine(title: "Time", value: record.date.vaultTime)
                InfoLine(title: "Repeat", value: record["recurrence"].isEmpty ? "Never" : record["recurrence"])
                linkedRecord("Related Record", id: record["relatedID"], historicalName: record["relatedName"])
                if !store.preferences.customNotifications { Text("Notifications are off. Enable Custom Reminders in Settings to receive alerts.").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
    func detailFields(_ record: VaultRecord, keys: [(String, String)]) -> some View {
        ForEach(keys, id: \.1) { item in InfoLine(title: item.0, value: record[item.1]) }
    }
    @ViewBuilder func installationInfo(_ record: VaultRecord) -> some View {
        if let date = ISO8601DateFormatter().date(from: record["installedDate"]) { InfoLine(title: "Installed", value: store.date(date)) }
        mileageInfo(record)
    }
    func mileageInfo(_ record: VaultRecord) -> some View {
        InfoLine(title: "Mileage", value: record["mileage"].isEmpty ? "" : "\(record["mileage"]) \(record["distanceUnit"].isEmpty ? store.distanceSuffix : record["distanceUnit"])")
    }
    @ViewBuilder func linkedRecord(_ label: String, id: String, historicalName: String = "") -> some View {
        if let uuid = UUID(uuidString: id), let linked = store.record(uuid) {
            NavigationLink { RecordDetail(recordID: uuid) } label: { VStack(alignment: .leading, spacing: 4) { Text(label).font(.caption).foregroundStyle(.secondary); Text(linked.title) } }
        } else if !historicalName.isEmpty { InfoLine(title: label, value: historicalName + " · historical record") }
    }
    @ViewBuilder func relatedRecords(_ record: VaultRecord) -> some View {
        if record.kind == .part || record.kind == .tire {
            let related = store.database.records.filter { $0.vehicleID == record.vehicleID && !$0.archived && ($0.kind == .replacement || $0.kind == .tireChange) && ($0["installedID"] == record.id.uuidString || $0["removedID"] == record.id.uuidString) }.sorted { $0.date > $1.date }
            Section(record.kind == .tire ? "Installation History" : "Related Replacements") {
                if related.isEmpty { Text("No historical records yet").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(related) { item in NavigationLink { RecordDetail(recordID: item.id) } label: { RecordRow(record: item) } }
            }
        }
    }
    @ViewBuilder func actions(_ record: VaultRecord) -> some View {
        if record.kind == .document { Button("Replace with New Document") {
            var draft = record
            draft.id = UUID(); draft.created = Date(); draft.date = Date(); draft.archived = false
            draft["number"] = ""
            if draft.expiration != nil { draft.expiration = Calendar.current.date(byAdding: .year, value: 1, to: Date()) }
            replacement = draft
        } }
        if record.kind == .reminder && !record.completed { Button("Mark Completed") { store.completeReminder(record) } }
        if record.kind == .part {
            if record.status != "Installed" { Button("Mark Installed") { var next = record; next.status = "Installed"; next["installedDate"] = ISO8601DateFormatter().string(from: Date()); _ = store.saveRecord(next) } }
            if record.status != "Removed" { Button("Mark Removed") { var next = record; next.status = "Removed"; _ = store.saveRecord(next) } }
        }
        if record.kind == .tire {
            if record.status != "Installed" { Button("Install Set") {
                var change = VaultRecord(vehicleID: record.vehicleID, kind: .tireChange)
                change.title = "Install \(record.title)"; change["installedID"] = record.id.uuidString
                change["removedID"] = store.records(.tire, vehicleID: record.vehicleID).first(where: { $0.status == "Installed" })?.id.uuidString ?? ""
                tireChange = change
            } }
            if record.status != "Stored" { Button("Mark Stored") { var next = record; next.status = "Stored"; _ = store.saveRecord(next) } }
            if record.status != "Retired" { Button("Retire Set") { var next = record; next.status = "Retired"; _ = store.saveRecord(next) } }
        }
    }
}
