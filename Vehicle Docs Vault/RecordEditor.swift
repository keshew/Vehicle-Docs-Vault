import SwiftUI

struct RecordEditor: View {
    @EnvironmentObject var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    @State private var record: VaultRecord
    @State private var originalRecord: VaultRecord
    @State private var noExpiration: Bool
    @State private var hasInstalledDate: Bool
    @State private var installedDate: Date
    @State private var hasPurchaseDate: Bool
    @State private var purchaseDate: Date
    @State private var pending: [PendingAttachment] = []
    @State private var creatingPart = false
    @State private var notify = false
    @State private var saving = false
    @State private var loadingAttachments = false
    @State private var creatingTire = false
    @State private var initialized = false
    @State private var originalNotify = false
    @State private var discardChanges = false
    var replacingDocumentID: UUID?
    private let editing: Bool
    var onSaved: ((UUID) -> Void)?
    init(kind: RecordKind, vehicleID: UUID, record: VaultRecord? = nil, creating: Bool = false, replacingDocumentID: UUID? = nil, onSaved: ((UUID) -> Void)? = nil) {
        var initial = record ?? VaultRecord(vehicleID: vehicleID, kind: kind)
        if record == nil {
            initial.category = kind.categories.first ?? ""
            initial.status = kind == .part || kind == .tire ? "Stored" : ""
            initial["quantity"] = "1"
            initial["recurrence"] = "Never"
            if kind == .document { initial.expiration = Calendar.current.date(byAdding: .year, value: 1, to: Date()) }
        }
        if kind == .reminder && initial["recurrence"].isEmpty { initial["recurrence"] = "Never" }
        _record = State(initialValue: initial)
        _originalRecord = State(initialValue: initial)
        _noExpiration = State(initialValue: initial.expiration == nil)
        _hasInstalledDate = State(initialValue: !initial["installedDate"].isEmpty)
        _installedDate = State(initialValue: ISO8601DateFormatter().date(from: initial["installedDate"]) ?? Date())
        _hasPurchaseDate = State(initialValue: !initial["purchaseDate"].isEmpty)
        _purchaseDate = State(initialValue: ISO8601DateFormatter().date(from: initial["purchaseDate"]) ?? Date())
        editing = record != nil && !creating
        self.onSaved = onSaved
        self.replacingDocumentID = replacingDocumentID
    }
    var prepared: VaultRecord {
        var value = record
        value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.title.isEmpty && value.kind == .tire { value.title = [value["manufacturer"], value["model"], value.category].filter { !$0.isEmpty }.joined(separator: " ") }
        if value.title.isEmpty && value.kind == .tireChange {
            let installed = UUID(uuidString: value["installedID"]).flatMap(store.record)
            let removed = UUID(uuidString: value["removedID"]).flatMap(store.record)
            value.title = removed.map { "\($0.category) → \(installed?.category ?? "Tires")" } ?? "Install \(installed?.title ?? "Tire Set")"
        }
        if value.kind == .document { value.expiration = noExpiration ? nil : (value.expiration ?? Date()) }
        if value.kind == .part || value.kind == .tire { value["installedDate"] = hasInstalledDate ? ISO8601DateFormatter().string(from: installedDate) : "" }
        if value.kind == .tire { value["purchaseDate"] = hasPurchaseDate ? ISO8601DateFormatter().string(from: purchaseDate) : "" }
        if !value["mileage"].isEmpty && value["distanceUnit"].isEmpty { value["distanceUnit"] = store.distanceSuffix }
        return value
    }
    var valid: Bool { validationMessage.isEmpty }
    var hasChanges: Bool {
        if record != originalRecord || !pending.isEmpty || loadingAttachments || notify != originalNotify { return true }
        if noExpiration != (originalRecord.expiration == nil) { return true }
        if hasInstalledDate != !originalRecord["installedDate"].isEmpty || hasPurchaseDate != !originalRecord["purchaseDate"].isEmpty { return true }
        if hasInstalledDate, let original = ISO8601DateFormatter().date(from: originalRecord["installedDate"]), installedDate != original { return true }
        if hasPurchaseDate, let original = ISO8601DateFormatter().date(from: originalRecord["purchaseDate"]), purchaseDate != original { return true }
        return false
    }
    var body: some View {
        Form {
            Section {
                VaultEditorHeading(title: editing ? "Refine the details." : "Every detail belongs.", subtitle: editing ? "Keep this record precise and up to date." : "Add a \(record.kind.title.lowercased()) to your vehicle's personal archive.", symbol: record.kind.symbol)
            }.listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)).listRowBackground(Color.clear)
            Section("Related Vehicle") {
                Picker("Vehicle", selection: $record.vehicleID) {
                    ForEach(store.database.vehicles.filter { !$0.archived || $0.id == record.vehicleID }) { Text($0.title).tag($0.id) }
                }.disabled(replacingDocumentID != nil).onChange(of: record.vehicleID) { _ in
                    for key in ["installedID", "removedID", "relatedID", "installedName", "removedName", "relatedName"] { record[key] = "" }
                }
            }
            Section("Basic Information") {
                TextField("\(record.kind.title) Name\([RecordKind.tire, .tireChange].contains(record.kind) ? " (optional)" : " *")", text: $record.title)
                if !record.kind.categories.isEmpty {
                    Picker(record.kind == .tire ? "Season" : "Category", selection: $record.category) { ForEach(record.kind.categories, id: \.self) { Text($0) } }
                }
            }
            kindFields
            if record.kind != .note { Section("Notes") { TextField("Additional details", text: $record.notes, axis: .vertical).lineLimit(3...10) } }
            Section("Attachments") {
                PendingAttachmentsPicker(pending: $pending, loading: $loadingAttachments)
                if editing { AttachmentLinks(ownerID: record.id).disabled(loadingAttachments || saving) }
            }
            Section {
                Button { save() } label: { HStack { Spacer(); if saving { ProgressView() }; Text(editing ? "Save Changes" : "Save \(record.kind.title)").fontWeight(.semibold); Spacer() } }.buttonStyle(VaultPrimaryButton()).listRowInsets(EdgeInsets()).listRowBackground(Color.clear).disabled(!valid || saving || loadingAttachments)
            } footer: {
                if !valid { Text(validationMessage).foregroundStyle(.secondary) }
            }
        }.disabled(saving).vaultEditorSafety(hasChanges: hasChanges, isBusy: saving, confirmDiscard: $discardChanges).vaultListAppearance().navigationTitle("\(editing ? "Edit" : "Add") \(record.kind.title)").navigationBarTitleDisplayMode(.inline).vaultErrorBanner()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if hasChanges { discardChanges = true } else { dismiss() } }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!valid || saving || loadingAttachments) }
            }
            .sheet(isPresented: $creatingPart) {
                NavigationStack { RecordEditor(kind: .part, vehicleID: record.vehicleID, onSaved: { record["installedID"] = $0.uuidString }) }
            }
            .sheet(isPresented: $creatingTire) {
                NavigationStack { RecordEditor(kind: .tire, vehicleID: record.vehicleID, onSaved: { record["installedID"] = $0.uuidString }) }
            }
            .onAppear { if !initialized { initialized = true; notify = store.preferences.customNotifications; originalNotify = notify } }
    }
    @ViewBuilder var kindFields: some View {
        switch record.kind {
        case .document: documentFields
        case .part: partFields
        case .replacement: replacementFields
        case .tire: tireFields
        case .tireChange: tireChangeFields
        case .note: noteFields
        case .reminder: reminderFields
        }
    }
    var documentFields: some View {
        Group {
            Section("Identification") { field("Document Number", "number"); field("Issuing Organization", "issuer") }
            Section("Dates") {
                DatePicker("Issue Date", selection: $record.date, displayedComponents: .date)
                Toggle("No Expiration Date", isOn: $noExpiration)
                if !noExpiration { DatePicker("Expiration Date", selection: Binding(get: { record.expiration ?? Date() }, set: { record.expiration = $0 }), displayedComponents: .date) }
            }
        }
    }
    var partFields: some View {
        Group {
            Section("Part Details") {
                field("Manufacturer", "manufacturer")
                field("Part Number", "partNumber")
                field("Model", "model")
                TextField("Quantity", text: value("quantity")).keyboardType(.numberPad)
                Picker("Status", selection: $record.status) { ForEach(["Installed", "Stored", "Removed"], id: \.self) { Text($0) } }
            }
            Section("Installation & Storage") {
                Toggle("Installation Date", isOn: $hasInstalledDate)
                if hasInstalledDate { DatePicker("Installed", selection: $installedDate, displayedComponents: .date) }
                mileageField
                field("Storage Location", "location")
                Text("Storage location is a label you enter, such as Garage Shelf A.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    var replacementFields: some View {
        Group {
            Section("Replacement Record") {
                DatePicker("Date", selection: $record.date, displayedComponents: .date)
                mileageField
                relationPicker("Removed Part", key: "removedID", kind: .part)
                relationPicker("Installed Part", key: "installedID", kind: .part)
                Button { creatingPart = true } label: { Label("Create New Installed Part", systemImage: "plus.circle") }
            }
        }
    }
    var tireFields: some View {
        Group {
            Section("Tire Specification") {
                field("Manufacturer *", "manufacturer")
                field("Model", "model")
                TextField("Width (e.g. 225) *", text: value("width")).keyboardType(.numberPad)
                TextField("Aspect Ratio (e.g. 45) *", text: value("ratio")).keyboardType(.numberPad)
                TextField("Rim Size (e.g. 18) *", text: value("rim")).keyboardType(.numberPad)
                Picker("Status", selection: $record.status) { ForEach(["Installed", "Stored", "Retired"], id: \.self) { Text($0) } }
            }
            Section("Purchase & Storage") {
                Toggle("Purchase Date", isOn: $hasPurchaseDate)
                if hasPurchaseDate { DatePicker("Purchased", selection: $purchaseDate, displayedComponents: .date) }
                TextField("Production Year", text: value("productionYear")).keyboardType(.numberPad)
                field("Storage Location", "location")
                Toggle("Installation Date", isOn: $hasInstalledDate)
                if hasInstalledDate { DatePicker("Installed", selection: $installedDate, displayedComponents: .date) }
                mileageField
            }
        }
    }
    var tireChangeFields: some View {
        Section("Tire Change") {
            relationPicker("Installed Tire Set *", key: "installedID", kind: .tire)
            relationPicker("Removed Tire Set", key: "removedID", kind: .tire)
            DatePicker("Date", selection: $record.date, displayedComponents: .date)
            mileageField
            Button { creatingTire = true } label: { Label("Create New Tire Set", systemImage: "plus.circle") }
        }
    }
    var noteFields: some View {
        Section("Note") {
            DatePicker("Date", selection: $record.date, displayedComponents: .date)
            TextField("Note Text *", text: $record.notes, axis: .vertical).lineLimit(6...20)
        }
    }
    var reminderFields: some View {
        Group {
            Section("Schedule") {
                DatePicker("Date & Time", selection: $record.date, displayedComponents: [.date, .hourAndMinute])
                Picker("Repeat", selection: value("recurrence")) { ForEach(["Never", "Monthly", "Every 3 Months", "Every 6 Months", "Yearly"], id: \.self) { Text($0) } }
                Picker("Related Record", selection: relationBinding("relatedID")) {
                    if record["relatedID"].isEmpty && !record["relatedName"].isEmpty {
                        Text("Historical: " + record["relatedName"]).tag("")
                        Text("None").tag("__clear__")
                    } else { Text("None").tag("") }
                    ForEach(store.database.records.filter { $0.vehicleID == record.vehicleID && (!$0.archived || $0.id.uuidString == record["relatedID"]) && $0.kind != .reminder }) { Text("\($0.kind.title): \($0.title)").tag($0.id.uuidString) }
                }
            }
            Section {
                Toggle("Custom Reminder Notifications", isOn: $notify)
            } footer: { Text("Enables notifications for all custom reminders. iOS will ask for permission only when you enable this option. Recurring reminders schedule the next six occurrences and refresh whenever you open the app.") }
        }
    }
    var mileageField: some View {
        HStack { TextField(record.kind == .replacement || record.kind == .tireChange ? "Mileage" : "Mileage at Installation", text: value("mileage")).keyboardType(.decimalPad); Text(record["distanceUnit"].isEmpty ? store.distanceSuffix : record["distanceUnit"]).foregroundStyle(.secondary) }
    }
    var validationMessage: String {
        if let issue = VaultIntegrity.recordIssue(prepared) { return issue }
        if prepared.kind == .reminder && notify && !prepared.completed && VaultRecurrence.months(prepared["recurrence"]) == nil {
            let minute = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: prepared.date)) ?? prepared.date
            if minute <= Date() { return "Choose a future date and time to receive a notification." }
        }
        return ""
    }
    func value(_ key: String) -> Binding<String> { Binding(get: { record[key] }, set: { record[key] = $0 }) }
    func field(_ title: String, _ key: String) -> some View { TextField(title, text: value(key)) }
    func relationBinding(_ key: String) -> Binding<String> {
        Binding(get: { record[key] }, set: { selection in
            record[key] = selection == "__clear__" ? "" : selection
            record[key.replacingOccurrences(of: "ID", with: "Name")] = ""
        })
    }
    func relationPicker(_ title: String, key: String, kind: RecordKind) -> some View {
        let nameKey = key.replacingOccurrences(of: "ID", with: "Name")
        let historicalName = record[key].isEmpty ? record[nameKey] : ""
        return Picker(title, selection: relationBinding(key)) {
            if historicalName.isEmpty { Text("None").tag("") }
            else { Text("Historical: " + historicalName).tag(""); Text("None").tag("__clear__") }
            ForEach(store.records(kind, vehicleID: record.vehicleID, includeArchived: true).filter { $0.id != record.id && (!$0.archived || $0.id.uuidString == record[key]) }) { Text($0.title).tag($0.id.uuidString) }
        }
    }
    func save() {
        guard valid, !saving, !loadingAttachments else { return }
        saving = true
        let value = prepared
        Task {
            guard await store.saveRecord(value, pending: pending, replacingDocumentID: replacingDocumentID) else { saving = false; return }
            pending = []
            if record.kind == .reminder && notify != store.preferences.customNotifications { await store.enableNotifications(documents: false, enabled: notify) }
            onSaved?(record.id)
            dismiss()
        }
    }
}
