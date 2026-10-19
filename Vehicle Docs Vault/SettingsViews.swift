import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject var store: VaultStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VaultPageHeading(eyebrow: "Tailored to you", title: "The way you like it.", subtitle: "Your preferences. Your personal archive.")
                appearanceSection
                garageSection
                preferencesSection
                notificationsSection
                dataSection
            }.padding(22).frame(maxWidth: 850).frame(maxWidth: .infinity)
        }.background(Color.vaultBackground).buttonStyle(.plain).navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
    }
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VaultSectionHeading(title: "Appearance")
            VaultCard {
                HStack(spacing: 10) {
                    ForEach(["System", "Light", "Dark"], id: \.self) { theme in
                        Button { store.updatePreferences { $0.appearance = theme } } label: {
                            VStack(spacing: 13) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 11).fill(theme == "Dark" ? Color.vaultNavy : Color(red: 0.94, green: 0.92, blue: 0.88))
                                    if theme == "System" { HStack(spacing: 0) { Color.clear; Color.vaultNavy }.clipShape(RoundedRectangle(cornerRadius: 11)) }
                                    VStack(alignment: .leading, spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(Color.vaultChampagne).frame(width: 17, height: 3); RoundedRectangle(cornerRadius: 2).fill(theme == "Dark" ? Color.white.opacity(0.18) : Color.black.opacity(0.12)).frame(height: 14); HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(Color.vaultChampagne.opacity(0.4)); RoundedRectangle(cornerRadius: 2).fill(Color.vaultChampagne.opacity(0.2)) }.frame(height: 13) }.padding(13)
                                }.frame(height: 72).overlay(RoundedRectangle(cornerRadius: 11).stroke(store.preferences.appearance == theme ? Color.vaultGold : .clear, lineWidth: 1.5))
                                HStack(spacing: 5) { Text(theme).font(.system(size: 11)); if store.preferences.appearance == theme { Circle().fill(Color.vaultGold).frame(width: 4, height: 4) } }.foregroundStyle(Color.vaultInk)
                            }.frame(maxWidth: .infinity)
                        }.buttonStyle(.plain).accessibilityAddTraits(store.preferences.appearance == theme ? [.isSelected] : [])
                    }
                }
            }
        }
    }
    private var garageSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VaultSectionHeading(title: "Your garage")
            VaultCard {
                VStack(spacing: 17) {
                    NavigationLink { DefaultVehicleView() } label: { settingsRow("Default vehicle", subtitle: store.preferences.defaultVehicleID.flatMap(store.vehicle)?.title ?? "First available", symbol: "car.side") }
                    Divider()
                    NavigationLink { VehiclesView() } label: { settingsRow("Manage vehicles", subtitle: "\(store.activeVehicles.count) in your collection", symbol: "square.stack.3d.up") }
                }
            }
        }
    }
    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VaultSectionHeading(title: "The finer preferences")
            VaultCard {
                VStack(spacing: 17) {
                    HStack { Image(systemName: "ruler").font(.system(size: 18, weight: .light)).foregroundStyle(Color.vaultGold).frame(width: 24); Picker("Distance", selection: Binding(get: { store.preferences.unit }, set: { store.changeDistanceUnit($0) })) { Text("Kilometers").tag("Kilometers"); Text("Miles").tag("Miles") }.font(.system(size: 13)) }
                    Divider()
                    HStack { Image(systemName: "calendar").font(.system(size: 18, weight: .light)).foregroundStyle(Color.vaultGold).frame(width: 24); Picker("Date format", selection: preference(\.dateFormat)) { ForEach(["DD/MM/YYYY", "MM/DD/YYYY", "YYYY/MM/DD"], id: \.self) { Text($0) } }.font(.system(size: 13)) }
                }
            }
            Text("Stored mileage is converted when you change units.").font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
    }
    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VaultSectionHeading(title: "A timely reminder")
            VaultCard {
                VStack(spacing: 18) {
                    Toggle("Document expirations", isOn: Binding(get: { store.preferences.documentNotifications }, set: { value in Task { await store.enableNotifications(documents: true, enabled: value) } })).font(.system(size: 13))
                    Divider()
                    Toggle("Custom reminders", isOn: Binding(get: { store.preferences.customNotifications }, set: { value in Task { await store.enableNotifications(documents: false, enabled: value) } })).font(.system(size: 13))
                    Divider()
                    NavigationLink { NotificationsSettings() } label: { settingsRow("Notification options", subtitle: "Timing & iOS permissions", symbol: "bell") }
                }
            }
        }
    }
    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VaultSectionHeading(title: "In your hands")
            VaultCard {
                VStack(spacing: 18) {
                    NavigationLink { ExportDataView() } label: { settingsRow("Export data", subtitle: "JSON or CSV", symbol: "square.and.arrow.up") }
                    Divider()
                    NavigationLink { ImportDataView() } label: { settingsRow("Import data", subtitle: "Restore from an export", symbol: "square.and.arrow.down") }
                    Divider()
                    NavigationLink { BackupView() } label: { settingsRow("Local backups", subtitle: store.backups.isEmpty ? "Create your first backup" : "\(store.backups.count) saved copies", symbol: "externaldrive") }
                    Divider()
                    NavigationLink { ArchivedRecordsView() } label: { settingsRow("Archived records", subtitle: "Kept, until you need them again", symbol: "archivebox") }
                }
            }
            NavigationLink { ResetDataView() } label: { HStack(spacing: 10) { Image(systemName: "trash"); Text("Reset app data"); Spacer(); Image(systemName: "chevron.right").font(.system(size: 9)) }.font(.system(size: 12)).foregroundStyle(Color(red: 0.65, green: 0.29, blue: 0.26)).padding(19).background(Color.red.opacity(0.035), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.09))) }
        }
    }
    func settingsRow(_ title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 14) { Image(systemName: symbol).font(.system(size: 19, weight: .ultraLight)).foregroundStyle(Color.vaultGold).frame(width: 25); VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.vaultInk); Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.system(size: 9, weight: .light)).foregroundStyle(.secondary) }.contentShape(Rectangle())
    }
    func preference(_ keyPath: WritableKeyPath<VaultPreferences, String>) -> Binding<String> {
        Binding(get: { store.preferences[keyPath: keyPath] }, set: { value in store.updatePreferences { $0[keyPath: keyPath] = value } })
    }
}

struct DefaultVehicleView: View {
    @EnvironmentObject var store: VaultStore
    var body: some View {
        List {
            if store.activeVehicles.isEmpty { VehicleRequired().listRowBackground(Color.clear) }
            ForEach(store.activeVehicles) { vehicle in
                Button { store.updatePreferences { $0.defaultVehicleID = vehicle.id } } label: {
                    HStack(spacing: 14) { VehicleThumbnail(vehicle: vehicle, size: 46); VStack(alignment: .leading, spacing: 4) { Text(vehicle.title).foregroundStyle(.primary); Text(vehicle.subtitle).font(.caption).foregroundStyle(.secondary) }; Spacer(); if store.preferences.defaultVehicleID == vehicle.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.vaultBlue) } }.padding(.vertical, 6)
                }
            }
        }.vaultListAppearance().navigationTitle("Default Vehicle").navigationBarTitleDisplayMode(.inline)
    }
}

struct NotificationsSettings: View {
    @EnvironmentObject var store: VaultStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var permission = "Checking…"
    var body: some View {
        Form {
            Section {
                Toggle("Document Expiration Notifications", isOn: Binding(get: { store.preferences.documentNotifications }, set: { value in Task { await store.enableNotifications(documents: true, enabled: value); await refreshPermission() } }))
                Picker("Remind", selection: Binding(get: { store.preferences.expirationLead }, set: { value in store.updatePreferences { $0.expirationLead = value } })) {
                    Text("Same Day").tag(0)
                    Text("1 Day Before").tag(1)
                    Text("3 Days Before").tag(3)
                    Text("7 Days Before").tag(7)
                    Text("30 Days Before").tag(30)
                }
            } header: { Text("Documents") } footer: { Text("Document alerts are delivered at 9:00 AM in your local time zone. Archived vehicles and records do not send alerts.") }
            Section {
                Toggle("Custom Reminders", isOn: Binding(get: { store.preferences.customNotifications }, set: { value in Task { await store.enableNotifications(documents: false, enabled: value); await refreshPermission() } }))
            } header: { Text("Reminders") } footer: { Text("The nearest 64 alerts are scheduled on this device. Open the app periodically to refresh future alerts.") }
            Section("iOS Permission") {
                InfoLine(title: "Status", value: permission)
                Button("Open Notification Settings") { if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) } }
            }
        }.vaultListAppearance().navigationTitle("Notifications").navigationBarTitleDisplayMode(.inline).task { await refreshPermission() }
            .onChange(of: scenePhase) { phase in if phase == .active { Task { await refreshPermission() } } }
    }
    func refreshPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: permission = "Allowed"
        case .denied: permission = "Disabled in iOS Settings"
        case .notDetermined: permission = "Not requested"
        @unknown default: permission = "Unavailable"
        }
    }
}

struct ExportDataView: View {
    @EnvironmentObject var store: VaultStore
    @State private var format = "JSON"
    @State private var selected = Set(RecordKind.allCases)
    @State private var vehicles = true
    @State private var document: VaultExportFile?
    @State private var exporting = false
    @State private var preparing = false
    @State private var success = false
    @State private var exportType: UTType = .json
    var body: some View {
        Form {
            Section {
                Picker("Format", selection: $format) { Text("JSON").tag("JSON"); Text("CSV").tag("CSV") }.pickerStyle(.segmented)
            } footer: { Text(format == "JSON" ? "JSON includes attachments and can be imported back into the app. Related vehicles and linked records are included automatically to preserve relationships." : "CSV is a readable table of your records. Attachments are not included. Use JSON for a restorable export.") }
            Section("Categories") {
                Toggle("Select All", isOn: Binding(get: { vehicles && selected.count == RecordKind.allCases.count }, set: { value in vehicles = value; selected = value ? Set(RecordKind.allCases) : [] }))
                Toggle("Vehicles", isOn: $vehicles)
                ForEach(RecordKind.allCases) { kind in
                    Toggle(kind.plural, isOn: Binding(get: { selected.contains(kind) }, set: { value in if value { selected.insert(kind) } else { selected.remove(kind) } }))
                }
            }
            Section {
                Button {
                    preparing = true
                    success = false
                    let requestedKinds = selected
                    let includeVehicles = vehicles
                    let isCSV = format == "CSV"
                    Task {
                        await Task.yield()
                        do {
                            let data = try await store.prepareExport(kinds: requestedKinds, vehicles: includeVehicles, csv: isCSV)
                            document = VaultExportFile(data: data)
                            exportType = isCSV ? .commaSeparatedText : .json
                            exporting = true
                        } catch { store.errorMessage = error.localizedDescription }
                        preparing = false
                    }
                } label: { HStack { if preparing { ProgressView() }; Label("Create Export", systemImage: "square.and.arrow.up") } }.disabled(preparing || (selected.isEmpty && !vehicles))
                if success { Label("Export saved", systemImage: "checkmark.circle.fill").foregroundStyle(.teal) }
            }
        }.disabled(preparing).vaultListAppearance().navigationTitle("Export Data").navigationBarTitleDisplayMode(.inline)
            .fileExporter(isPresented: $exporting, document: document, contentType: exportType, defaultFilename: "Vehicle-Docs-Vault") { result in
                switch result { case .success: success = true; case .failure(let error): if !VaultErrors.isCancellation(error) { store.errorMessage = error.localizedDescription } }
            }
    }
}

struct ImportDataView: View {
    @EnvironmentObject var store: VaultStore
    @State private var importing = false
    @State private var preview: BackupEnvelope?
    @State private var loading = false
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "square.and.arrow.down").font(.largeTitle).foregroundStyle(Color.vaultBlue)
                    Text("Bring your vault back.").font(.title2.weight(.bold))
                    Text("Select a JSON export or backup created by Vehicle Docs Vault. You can review its contents before importing.").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 16)
                Button { importing = true } label: { Label("Select File", systemImage: "folder") }.disabled(loading)
                if loading { ProgressView("Reading file…") }
            }
            if let preview { ImportPreview(envelope: preview).id(preview.created) }
        }.vaultListAppearance().navigationTitle("Import Data").navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    loading = true
                    Task {
                        await Task.yield()
                        preview = nil
                        do { preview = try await store.readImport(url) } catch { store.errorMessage = error.localizedDescription }
                        loading = false
                    }
                } catch { if !VaultErrors.isCancellation(error) { store.errorMessage = error.localizedDescription } }
            }
    }
}

struct ImportPreview: View {
    @EnvironmentObject var store: VaultStore
    var envelope: BackupEnvelope
    @State private var confirming = false
    @State private var restoring = false
    @State private var success = false
    var body: some View {
        Section("File Preview") {
            InfoLine(title: "Created", value: store.date(envelope.created))
            InfoLine(title: "Vehicles", value: "\(envelope.database.vehicles.count)")
            ForEach(RecordKind.allCases) { kind in InfoLine(title: kind.plural, value: "\(envelope.database.records.filter { $0.kind == kind }.count)") }
            InfoLine(title: "Attachments", value: "\(envelope.database.attachments.count)")
        }
        Section {
            Button { confirming = true } label: { HStack { if restoring { ProgressView() }; Label("Import Data", systemImage: "square.and.arrow.down") } }.disabled(restoring)
            if success { Label("Your data has been restored", systemImage: "checkmark.circle.fill").foregroundStyle(.teal) }
        } footer: { Text("Import replaces the current vault. A local backup of your current records is created first. Notification options are turned off after import; enable them again in Settings.") }
        .confirmationDialog("Replace the current vault with this file? A backup will be saved first.", isPresented: $confirming, titleVisibility: .visible) {
            Button("Back Up & Import", role: .destructive) {
                restoring = true
                Task { success = await store.restore(envelope); restoring = false }
            }
        }
    }
}

struct BackupView: View {
    @EnvironmentObject var store: VaultStore
    @State private var preview: BackupEnvelope?
    @State private var deletion: LocalBackup?
    @State private var deleting = false
    @State private var creating = false
    @State private var created = false
    var body: some View {
        List {
            Section {
                if let last = store.backups.first {
                    InfoLine(title: "Last Backup", value: store.date(last.date) + " · " + last.date.vaultTime)
                    InfoLine(title: "Backup Size", value: VaultFormatting.fileSize(last.size))
                } else { Text("No local backups yet").foregroundStyle(.secondary) }
                Button {
                    creating = true
                    Task { created = await store.createBackup(); creating = false }
                } label: { HStack { if creating { ProgressView() }; Label("Create Backup", systemImage: "externaldrive.badge.plus") } }.disabled(creating)
                if created { Label("Backup created", systemImage: "checkmark.circle.fill").foregroundStyle(.teal) }
            } header: { Text("Local Backups") } footer: { Text("Backups include your records and attachments. They stay inside this app on this device. Save a JSON export in Files for a separate copy.") }
            Section("Saved Backups") {
                ForEach(store.backups) { backup in
                    HStack {
                        Button {
                            Task { do { preview = try await store.readImport(backup.url) } catch { store.errorMessage = error.localizedDescription } }
                        } label: { VStack(alignment: .leading, spacing: 5) { Text(store.date(backup.date) + " · " + backup.date.vaultTime).font(.subheadline.weight(.medium)); Text(VaultFormatting.fileSize(backup.size)).font(.caption).foregroundStyle(.secondary); Text("Review & Restore").font(.caption) } }
                        Spacer()
                        Button(role: .destructive) { deletion = backup; deleting = true } label: { Image(systemName: "trash") }.buttonStyle(.borderless).accessibilityLabel("Delete backup")
                    }.padding(.vertical, 6)
                }
            }
            if let preview { ImportPreview(envelope: preview).id(preview.created) }
        }.vaultListAppearance().navigationTitle("Backup").navigationBarTitleDisplayMode(.inline).onAppear { store.refreshBackups() }
            .confirmationDialog("Delete this local backup?", isPresented: $deleting, titleVisibility: .visible) { Button("Delete Backup", role: .destructive) { if let deletion { store.deleteBackup(deletion); preview = nil } } }
    }
}

struct ArchivedRecordsView: View {
    @EnvironmentObject var store: VaultStore
    @State private var category = "Documents"
    @State private var deletion: UUID?
    @State private var confirming = false
    var kind: RecordKind { category == "Parts" ? .part : category == "Notes" ? .note : category == "Tires" ? .tire : .document }
    var records: [VaultRecord] { store.database.records.filter { $0.archived && $0.kind == kind } }
    var body: some View {
        List {
            Section { Picker("Type", selection: $category) { ForEach(["Documents", "Parts", "Vehicles", "Notes", "Tires", "Replacements", "Tire Changes", "Reminders"], id: \.self) { Text($0) } } }
            if category == "Vehicles" {
                let vehicles = store.database.vehicles.filter(\.archived)
                if vehicles.isEmpty { empty }
                ForEach(vehicles) { vehicle in
                    NavigationLink { VehicleDetail(vehicleID: vehicle.id) } label: { HStack(spacing: 12) { VehicleThumbnail(vehicle: vehicle, size: 48); Text(vehicle.title) } }
                        .swipeActions(edge: .leading) { Button("Restore") { store.setArchived(vehicle: vehicle, archived: false) }.tint(.teal) }
                        .swipeActions { Button("Delete", role: .destructive) { deletion = vehicle.id; confirming = true } }
                }
            } else {
                let archiveKind: RecordKind = category == "Replacements" ? .replacement : category == "Tire Changes" ? .tireChange : category == "Reminders" ? .reminder : kind
                let items = store.database.records.filter { $0.archived && $0.kind == archiveKind }
                if items.isEmpty { empty }
                ForEach(items) { record in
                    NavigationLink { RecordDetail(recordID: record.id) } label: { RecordRow(record: record, showVehicle: true) }
                        .swipeActions(edge: .leading) { Button("Restore") { store.setArchived(record: record, archived: false) }.tint(.teal) }
                        .swipeActions { Button("Delete", role: .destructive) { deletion = record.id; confirming = true } }
                }
            }
        }.vaultListAppearance().navigationTitle("Archived Records").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Permanently delete this archived record and its attachments?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Delete Permanently", role: .destructive) { if let deletion { if category == "Vehicles" { store.deleteVehicle(deletion) } else { store.deleteRecord(deletion) } } }
            }
    }
    var empty: some View { EmptyVault(symbol: "archivebox", title: "Nothing archived here", message: "Archived records stay available until you choose to delete them.").listRowBackground(Color.clear) }
}

struct ResetDataView: View {
    @EnvironmentObject var store: VaultStore
    @State private var first = false
    @State private var second = false
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.red)
                    Text("Reset your vault").font(.title2.weight(.bold))
                    Text("This will permanently remove all vehicles, documents, parts, notes, reminders and attachments stored in the app.")
                    Text("Local backups and preferences will also be removed. Export your data first if you want to keep a copy.").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 14)
                NavigationLink("Export Data First") { ExportDataView() }
                Button("Reset All Data", role: .destructive) { first = true }
            }
        }.vaultListAppearance().navigationTitle("Reset App Data").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Reset all app data?", isPresented: $first, titleVisibility: .visible) { Button("Continue to Reset", role: .destructive) { second = true } }
            .alert("Permanently delete everything?", isPresented: $second) { Button("Cancel", role: .cancel) { }; Button("Reset All Data", role: .destructive) { store.reset() } } message: { Text("This is the final confirmation. Records, attachments and local backups cannot be recovered after reset.") }
    }
}
