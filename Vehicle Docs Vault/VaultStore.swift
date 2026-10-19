import Foundation
import SwiftUI
import Combine
import UserNotifications
import UniformTypeIdentifiers

@MainActor
final class VaultStore: ObservableObject {
    @Published private(set) var database = VaultDatabase()
    @Published var errorMessage: String?
    @Published var noticeMessage: String?
    @Published private(set) var generation = UUID()
    @Published var backups: [LocalBackup] = []
    @Published private(set) var isTransferring = false
    @Published private(set) var loadIssue: String?
    @Published private(set) var revision = 0
    private(set) var root: URL
    private var dataURL: URL { root.appendingPathComponent("vault.json") }
    var attachmentDirectory: URL { root.appendingPathComponent("Attachments", isDirectory: true) }
    private var backupDirectory: URL { root.appendingPathComponent("Backups", isDirectory: true) }
    private let fm = FileManager.default
    private var loadedSafely = true
    private var schedulingNotifications = false
    private var notificationNeedsRefresh = false
    private var documentPermissionRevision = 0
    private var customPermissionRevision = 0
    private var lastClockDay = Date().vaultDay

    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VehicleDocsVault", isDirectory: true)
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            try fm.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
            try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            if fm.fileExists(atPath: dataURL.path) {
                let restored = VaultIntegrity.normalizeNavigation(try Self.decoder().decode(VaultDatabase.self, from: Data(contentsOf: dataURL)))
                try VaultIntegrity.validateDatabase(restored)
                database = restored
            } else {
                try persist(database)
            }
            if let preferred = database.preferences.defaultVehicleID, activeVehicles.contains(where: { $0.id == preferred }) {
                database.selectedVehicleID = preferred
            }
        } catch {
            loadedSafely = false
            loadIssue = "Your vault could not be opened. Existing files have been preserved. \(error.localizedDescription)"
        }
        refreshBackups()
        if loadedSafely {
            let missing = database.attachments.contains { !fm.fileExists(atPath: fileURL($0).path) }
            if missing { errorMessage = "Some attachment files are missing. Your records are intact. Restore a complete backup to recover the files." }
            isTransferring = true
            Task { @MainActor in
                defer { isTransferring = false }
                do { try await VaultTransfer.shared.cleanAttachments(directory: attachmentDirectory, keeping: Set(database.attachments.map(\.fileName))) }
                catch { errorMessage = "Temporary files could not be cleaned up. Your saved records are intact. \(error.localizedDescription)" }
            }
        }
    }

    var preferences: VaultPreferences { database.preferences }
    var activeVehicles: [Vehicle] { database.vehicles.filter { !$0.archived } }
    var selectedVehicle: Vehicle? { activeVehicles.first { $0.id == database.selectedVehicleID } ?? activeVehicles.first }
    var distanceSuffix: String { preferences.unit == "Miles" ? "mi" : "km" }
    var colorScheme: ColorScheme? { preferences.appearance == "Light" ? .light : preferences.appearance == "Dark" ? .dark : nil }
    func records(_ kind: RecordKind, vehicleID: UUID? = nil, includeArchived: Bool = false) -> [VaultRecord] {
        database.records.filter { $0.kind == kind && (vehicleID == nil || $0.vehicleID == vehicleID) && (includeArchived || !$0.archived) }
    }
    func vehicle(_ id: UUID) -> Vehicle? { database.vehicles.first { $0.id == id } }
    func record(_ id: UUID) -> VaultRecord? { database.records.first { $0.id == id } }
    func attachments(for id: UUID) -> [VaultAttachment] { database.attachments.filter { $0.ownerID == id } }
    func fileURL(_ item: VaultAttachment) -> URL { attachmentDirectory.appendingPathComponent(item.fileName) }
    func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = preferences.dateFormat == "MM/DD/YYYY" ? "MM/dd/yyyy" : preferences.dateFormat == "YYYY/MM/DD" ? "yyyy/MM/dd" : "dd/MM/yyyy"
        return formatter.string(from: date)
    }
    func expirationText(_ record: VaultRecord) -> String {
        guard let expiry = record.expiration else { return "No expiration date" }
        let days = Calendar.current.dateComponents([.day], from: Date().vaultDay, to: expiry.vaultDay).day ?? 0
        if days < 0 { return "Expired \(abs(days)) day\(days == -1 ? "" : "s") ago" }
        if days == 0 { return "Expires today" }
        return "\(days) days remaining · \(date(expiry))"
    }
    static func encoder() -> JSONEncoder { VaultCodec.encoder() }
    static func decoder() -> JSONDecoder { VaultCodec.decoder() }
    private func persist(_ value: VaultDatabase) throws {
        try Self.encoder().encode(value).write(to: dataURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    @discardableResult
    func commit(_ operation: (inout VaultDatabase) -> Void) -> Bool {
        transact(operation: operation)
    }
    private func transact(staged: [VaultAttachment] = [], operation: (inout VaultDatabase) -> Void) -> Bool {
        guard loadedSafely else { errorMessage = "Restore a backup or reset the vault before saving records. Your original files are intact."; return false }
        guard !isTransferring || !staged.isEmpty else { errorMessage = "Wait for the current data operation to finish."; return false }
        var next = database
        do {
            operation(&next)
            next.attachments.append(contentsOf: staged)
            for ownerID in Set(staged.map(\.ownerID)) {
                if let index = next.vehicles.firstIndex(where: { $0.id == ownerID }), next.vehicles[index].coverID == nil {
                    next.vehicles[index].coverID = next.attachments.first(where: { $0.ownerID == ownerID && !$0.isPDF })?.id
                }
            }
            try VaultIntegrity.validateDatabase(next)
            try persist(next)
            database = next
            revision += 1
            Task { await scheduleNotifications() }
            return true
        } catch { errorMessage = "Could not save changes. \(error.localizedDescription)"; return false }
    }
    private func withAttachments(_ drafts: [PendingAttachment], vehicleID: UUID, ownerID: UUID, category: String, save: ([VaultAttachment]) -> Bool) async -> Bool {
        guard !isTransferring else { errorMessage = "Wait for the current data operation to finish."; return false }
        guard !drafts.isEmpty else { return save([]) }
        isTransferring = true
        defer { isTransferring = false }
        do {
            let staged = try await VaultTransfer.shared.stageAttachments(drafts, directory: attachmentDirectory, vehicleID: vehicleID, ownerID: ownerID, category: category)
            if save(staged) { return true }
            try? await VaultTransfer.shared.removeFiles(staged.map(fileURL))
        } catch { errorMessage = "Could not save attachments. \(error.localizedDescription)" }
        return false
    }
    func selectVehicle(_ id: UUID) { commit { $0.selectedVehicleID = id } }
    func updatePreferences(_ change: (inout VaultPreferences) -> Void) { commit { change(&$0.preferences) } }
    @discardableResult
    func saveVehicle(_ input: Vehicle) -> Bool { saveVehiclePrepared(input, staged: []) }
    func saveVehicle(_ input: Vehicle, pending: [PendingAttachment]) async -> Bool {
        await withAttachments(pending, vehicleID: input.id, ownerID: input.id, category: "Vehicle Photos") { saveVehiclePrepared(input, staged: $0) }
    }
    private func saveVehiclePrepared(_ input: Vehicle, staged: [VaultAttachment]) -> Bool {
        var value = input
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let issue = VaultIntegrity.vehicleIssue(value) { errorMessage = issue; return false }
        if let mileage = VaultNumbers.decimal(value["mileage"]) { value["mileage"] = VaultNumbers.canonical(mileage) }
        if let cover = value.coverID, !database.attachments.contains(where: { $0.id == cover && $0.ownerID == value.id }) { value.coverID = nil }
        let previous = database.vehicles.first { $0.id == input.id }
        if value["mileage"].isEmpty { value["mileageRecordedAt"] = "" }
        else if previous == nil || previous?["mileage"] != value["mileage"] {
            value["mileageRecordedAt"] = ISO8601DateFormatter().string(from: Date())
        } else { value["mileageRecordedAt"] = previous?["mileageRecordedAt"] ?? value["mileageRecordedAt"] }
        return transact(staged: staged) { db in
            if let index = db.vehicles.firstIndex(where: { $0.id == value.id }) { db.vehicles[index] = value }
            else {
                db.vehicles.append(value)
                db.selectedVehicleID = value.id
                if db.preferences.defaultVehicleID == nil { db.preferences.defaultVehicleID = value.id }
                db.events.append(VaultEvent(vehicleID: value.id, targetID: value.id, title: "Vehicle added"))
            }
        }
    }
    @discardableResult
    func saveRecord(_ input: VaultRecord) -> Bool { saveRecordPrepared(input, staged: [], replacingDocumentID: nil) }
    func saveRecord(_ input: VaultRecord, pending: [PendingAttachment], replacingDocumentID: UUID? = nil) async -> Bool {
        let category = input.kind == .document ? "Documents" : input.kind == .replacement ? "Receipts" : input.kind == .part ? "Part Photos" : "Other"
        return await withAttachments(pending, vehicleID: input.vehicleID, ownerID: input.id, category: category) { saveRecordPrepared(input, staged: $0, replacingDocumentID: replacingDocumentID) }
    }
    private func saveRecordPrepared(_ input: VaultRecord, staged: [VaultAttachment], replacingDocumentID: UUID?) -> Bool {
        var value = input
        value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let issue = VaultIntegrity.recordIssue(value) { errorMessage = issue; return false }
        if let mileage = VaultNumbers.decimal(value["mileage"]) { value["mileage"] = VaultNumbers.canonical(mileage) }
        if value.kind == .reminder {
            value.date = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: value.date)) ?? value.date
            let previous = record(value.id)
            if previous?.date != value.date || previous?["recurrence"] != value["recurrence"] { value["recurrenceAnchor"] = ISO8601DateFormatter().string(from: value.date) }
        }
        if let oldID = replacingDocumentID {
            guard let old = record(oldID), old.kind == .document, value.kind == .document, old.id != value.id, old.vehicleID == value.vehicleID else { errorMessage = "The document being replaced is no longer available for this vehicle."; return false }
        }
        for (key, nameKey) in [("installedID", "installedName"), ("removedID", "removedName"), ("relatedID", "relatedName")] {
            if let id = UUID(uuidString: value[key]), let linked = record(id) { value[nameKey] = linked.title }
        }
        return transact(staged: staged) { db in
            let isNew = !db.records.contains { $0.id == value.id }
            let previous = db.records.first { $0.id == value.id }
            if [.part, .tire].contains(value.kind), previous?.status != value.status, previous != nil || value.status == "Installed" {
                value["stateChangedAt"] = ISO8601DateFormatter().string(from: Date())
                if value.status == "Installed" && value["installedDate"].isEmpty { value["installedDate"] = value["stateChangedAt"] }
            }
            if let oldID = replacingDocumentID, let index = db.records.firstIndex(where: { $0.id == oldID }) {
                db.records[index].archived = true
                db.events.append(VaultEvent(vehicleID: value.vehicleID, targetID: oldID, kind: .document, title: "\(db.records[index].title) · replaced"))
            }
            if let index = db.records.firstIndex(where: { $0.id == value.id }) { db.records[index] = value } else { db.records.append(value) }
            for index in db.attachments.indices where db.attachments[index].ownerID == value.id { db.attachments[index].vehicleID = value.vehicleID }
            if let previous, previous.vehicleID != value.vehicleID {
                db.events.removeAll { $0.targetID == value.id }
                for index in db.records.indices where db.records[index].id != value.id {
                    for (key, nameKey) in [("installedID", "installedName"), ("removedID", "removedName"), ("relatedID", "relatedName")] where db.records[index][key] == value.id.uuidString { db.records[index][nameKey] = value.title; db.records[index][key] = "" }
                }
            }
            let hasChangedRelation = previous?["installedID"] != value["installedID"] || previous?["removedID"] != value["removedID"] || previous?.date != value.date || previous?["mileage"] != value["mileage"] || previous?["distanceUnit"] != value["distanceUnit"]
            if !value.archived && (isNew || hasChangedRelation) && (value.kind == .replacement || value.kind == .tireChange) {
                let effective: VaultRecord
                if value.kind == .tireChange {
                    effective = db.records.filter { $0.kind == .tireChange && $0.vehicleID == value.vehicleID && !$0.archived }.max(by: { $0.date < $1.date }) ?? value
                } else { effective = value }
                let lastTireState = db.records.filter { $0.kind == .tire && $0.vehicleID == value.vehicleID }.compactMap { ISO8601DateFormatter().date(from: $0["stateChangedAt"]) }.max() ?? .distantPast
                let canApplyTireChange = lastTireState.vaultDay <= effective.date.vaultDay
                let installed = UUID(uuidString: effective["installedID"])
                let removed = UUID(uuidString: effective["removedID"])
                let installedIsActive = db.records.contains { $0.id == installed && !$0.archived }
                for index in db.records.indices {
                    if db.records[index].archived { continue }
                    if value.kind == .tireChange && (!canApplyTireChange || !installedIsActive) { continue }
                    let stateDate = ISO8601DateFormatter().date(from: db.records[index]["stateChangedAt"]) ?? .distantPast
                    if stateDate.vaultDay > effective.date.vaultDay { continue }
                    if value.kind == .tireChange && db.records[index].kind == .tire && db.records[index].vehicleID == value.vehicleID && db.records[index].id != installed && db.records[index].status == "Installed" { db.records[index].status = "Stored" }
                    if db.records[index].id == removed { db.records[index].status = value.kind == .tireChange ? "Stored" : "Removed"; db.records[index]["stateChangedAt"] = ISO8601DateFormatter().string(from: effective.date) }
                    if db.records[index].id == installed {
                        db.records[index].status = "Installed"
                        db.records[index]["installedDate"] = ISO8601DateFormatter().string(from: effective.date)
                        db.records[index]["mileage"] = effective["mileage"]
                        db.records[index]["distanceUnit"] = effective["distanceUnit"]
                        db.records[index]["stateChangedAt"] = ISO8601DateFormatter().string(from: effective.date)
                    }
                }
            }
            if value.kind == .tire && value.status == "Installed" && !value.archived {
                for index in db.records.indices where db.records[index].kind == .tire && db.records[index].vehicleID == value.vehicleID && db.records[index].id != value.id && !db.records[index].archived && db.records[index].status == "Installed" { db.records[index].status = "Stored" }
            }
            let action: String
            if let previous, previous.archived != value.archived { action = value.archived ? "archived" : "restored" }
            else { action = previous?.status != value.status && !value.status.isEmpty ? value.status.lowercased() : (isNew ? "added" : "updated") }
            db.events.append(VaultEvent(vehicleID: value.vehicleID, targetID: value.id, kind: value.kind, title: "\(value.displayTitle) · \(action)"))
        }
    }
    @discardableResult
    func setArchived(vehicle: Vehicle, archived: Bool) -> Bool {
        commit { db in
            guard let index = db.vehicles.firstIndex(where: { $0.id == vehicle.id }) else { return }
            db.vehicles[index].archived = archived
            if archived {
                let fallback = db.vehicles.first(where: { !$0.archived })?.id
                if db.selectedVehicleID == vehicle.id { db.selectedVehicleID = fallback }
                if db.preferences.defaultVehicleID == vehicle.id { db.preferences.defaultVehicleID = fallback }
            }
            db.events.append(VaultEvent(vehicleID: vehicle.id, targetID: vehicle.id, title: archived ? "Vehicle archived" : "Vehicle restored"))
        }
    }
    @discardableResult
    func setArchived(record: VaultRecord, archived: Bool) -> Bool {
        commit { db in
            guard let index = db.records.firstIndex(where: { $0.id == record.id }) else { return }
            db.records[index].archived = archived
            if !archived && record.kind == .tire && record.status == "Installed" && db.records.contains(where: { $0.id != record.id && $0.vehicleID == record.vehicleID && $0.kind == .tire && !$0.archived && $0.status == "Installed" }) { db.records[index].status = "Stored" }
            db.events.append(VaultEvent(vehicleID: record.vehicleID, targetID: record.id, kind: record.kind, title: "\(record.title) · \(archived ? "archived" : "restored")"))
        }
    }
    func completeReminder(_ record: VaultRecord) {
        commit { db in
            guard let index = db.records.firstIndex(where: { $0.id == record.id }), !db.records[index].completed else { return }
            db.records[index].completed = true
            if VaultRecurrence.months(record["recurrence"]) != nil,
               let due = VaultRecurrence.futureDates(for: record, after: max(Date(), record.date), count: 1).first {
                var next = record
                next.id = UUID(); next.completed = false; next.created = Date(); next.date = due
                if next["recurrenceAnchor"].isEmpty { next["recurrenceAnchor"] = ISO8601DateFormatter().string(from: record.date) }
                db.records.append(next)
            }
            db.events.append(VaultEvent(vehicleID: record.vehicleID, targetID: record.id, kind: .reminder, title: "\(record.title) · completed"))
        }
    }
    @discardableResult
    func deleteRecord(_ id: UUID) -> Bool {
        let files = attachments(for: id)
        let removedTitle = record(id)?.title ?? "Removed record"
        if commit({ db in
            db.records.removeAll { $0.id == id }
            db.attachments.removeAll { $0.ownerID == id }
            db.events.removeAll { $0.targetID == id }
            for index in db.records.indices {
                for (key, nameKey) in [("installedID", "installedName"), ("removedID", "removedName"), ("relatedID", "relatedName")] where db.records[index][key] == id.uuidString { db.records[index][nameKey] = removedTitle; db.records[index][key] = "" }
            }
        }) { removeAttachmentFiles(files); return true }
        return false
    }
    @discardableResult
    func deleteVehicle(_ id: UUID) -> Bool {
        let files = database.attachments.filter { $0.vehicleID == id }
        if commit({ db in
            db.vehicles.removeAll { $0.id == id }
            db.records.removeAll { $0.vehicleID == id }
            db.attachments.removeAll { $0.vehicleID == id }
            db.events.removeAll { $0.vehicleID == id }
            if db.selectedVehicleID == id { db.selectedVehicleID = db.vehicles.first(where: { !$0.archived })?.id }
            if db.preferences.defaultVehicleID == id { db.preferences.defaultVehicleID = db.vehicles.first(where: { !$0.archived })?.id }
        }) { removeAttachmentFiles(files); return true }
        return false
    }
    @discardableResult
    func addAttachments(_ pending: [PendingAttachment], vehicleID: UUID, ownerID: UUID, category: String) async -> Bool {
        guard !pending.isEmpty else { return true }
        return await withAttachments(pending, vehicleID: vehicleID, ownerID: ownerID, category: category) { files in transact(staged: files) { _ in } }
    }
    func renameAttachment(_ item: VaultAttachment, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        commit { db in if let index = db.attachments.firstIndex(where: { $0.id == item.id }) { db.attachments[index].name = name } }
    }
    @discardableResult
    func deleteAttachment(_ item: VaultAttachment) -> Bool {
        if commit({ db in
            db.attachments.removeAll { $0.id == item.id }
            for index in db.vehicles.indices where db.vehicles[index].coverID == item.id { db.vehicles[index].coverID = nil }
        }) { removeAttachmentFiles([item]); return true }
        return false
    }
    private func removeAttachmentFiles(_ files: [VaultAttachment]) {
        guard !files.isEmpty else { return }
        let urls = files.map(fileURL)
        Task {
            do { try await VaultTransfer.shared.removeFiles(urls) }
            catch { errorMessage = "The record was removed, but some file data could not be erased. Cleanup will be retried when the app next opens." }
        }
    }
    func rememberSearch(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        commit { $0.recentSearches.removeAll { $0 == value }; $0.recentSearches.insert(value, at: 0); $0.recentSearches = Array($0.recentSearches.prefix(8)) }
    }
    func prepareExport(kinds: Set<RecordKind>, vehicles: Bool, csv: Bool) async throws -> Data {
        guard !isTransferring else { throw VaultValidationError(message: "A data operation is already in progress.") }
        guard !kinds.isEmpty || vehicles else { throw VaultError.noData }
        isTransferring = true
        defer { isTransferring = false }
        return try await VaultTransfer.shared.export(database: database, directory: attachmentDirectory, kinds: kinds, vehicles: vehicles, csv: csv)
    }
    func readImport(_ url: URL) async throws -> BackupEnvelope {
        guard !isTransferring else { throw VaultValidationError(message: "A data operation is already in progress.") }
        isTransferring = true
        defer { isTransferring = false }
        return try await VaultTransfer.shared.read(url)
    }
    @discardableResult
    func restore(_ envelope: BackupEnvelope) async -> Bool {
        guard !isTransferring else { errorMessage = "Wait for the current data operation to finish."; return false }
        isTransferring = true
        defer { isTransferring = false }
        var created: [URL] = []
        do {
            try VaultIntegrity.validateEnvelope(envelope)
            try await writeBackup(allowRecoveryCopy: true)
            let staged = try await VaultTransfer.shared.stageRestore(envelope, directory: attachmentDirectory, clientID: database.clientID)
            created = staged.files
            try persist(staged.database)
            database = staged.database
            documentPermissionRevision += 1
            customPermissionRevision += 1
            revision += 1
            generation = UUID()
            noticeMessage = "Your vault has been restored. Notification preferences are off until you enable them again."
            loadedSafely = true; loadIssue = nil; errorMessage = nil
            do { try await VaultTransfer.shared.cleanAttachments(directory: attachmentDirectory, keeping: Set(database.attachments.map(\.fileName))) }
            catch { errorMessage = "Data was restored, but some old files could not be removed. \(error.localizedDescription)" }
            Task { await scheduleNotifications() }
            return true
        } catch {
            try? await VaultTransfer.shared.removeFiles(created)
            errorMessage = "Could not restore data. Your current vault is intact. \(error.localizedDescription)"
            return false
        }
    }
    @discardableResult
    func createBackup(allowRecoveryCopy: Bool = false) async -> Bool {
        guard !isTransferring else { errorMessage = "Wait for the current data operation to finish."; return false }
        isTransferring = true
        defer { isTransferring = false }
        do {
            try await writeBackup(allowRecoveryCopy: allowRecoveryCopy)
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    private func writeBackup(allowRecoveryCopy: Bool) async throws {
        let incomplete = database.attachments.contains { !fm.fileExists(atPath: fileURL($0).path) }
        if allowRecoveryCopy && (!loadedSafely || incomplete) {
            try await VaultTransfer.shared.recoveryCopy(root: root, destination: backupDirectory.appendingPathComponent("Recovery-" + UUID().uuidString, isDirectory: true))
        } else {
            guard loadedSafely else { throw VaultValidationError(message: "Restore a saved backup or import an export before creating a new backup.") }
            let url = backupDirectory.appendingPathComponent("Vault-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).json")
            try await VaultTransfer.shared.backup(database: database, attachments: attachmentDirectory, destination: url)
        }
        refreshBackups()
    }
    func refreshBackups() {
        backups = ((try? fm.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.fileSizeKey])) ?? []).compactMap { url -> LocalBackup? in
            let components = url.deletingPathExtension().lastPathComponent.split(separator: "-")
            guard url.pathExtension == "json", components.count >= 3,
                  let timestamp = TimeInterval(components[1]), let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return nil }
            return LocalBackup(url: url, date: Date(timeIntervalSince1970: timestamp), size: values.fileSize ?? 0)
        }.sorted { $0.date > $1.date }
    }
    func deleteBackup(_ backup: LocalBackup) {
        guard !isTransferring else { errorMessage = "Wait for the current data operation to finish."; return }
        do { try fm.removeItem(at: backup.url); refreshBackups() } catch { errorMessage = error.localizedDescription }
    }
    func reset() {
        guard !isTransferring else { errorMessage = "Wait for the current data operation to finish."; return }
        do {
            let fresh = VaultDatabase()
            try persist(fresh)
            database = fresh
            revision += 1
            generation = UUID()
            loadedSafely = true
            loadIssue = nil
            errorMessage = nil
            noticeMessage = nil
            documentPermissionRevision += 1
            customPermissionRevision += 1
            notificationNeedsRefresh = true
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            var cleanupFailed = false
            for directory in [attachmentDirectory, backupDirectory] {
                do {
                    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                    for url in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                        do { try fm.removeItem(at: url) } catch { cleanupFailed = true }
                    }
                } catch { cleanupFailed = true }
            }
            refreshBackups()
            notificationNeedsRefresh = true
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            if cleanupFailed { errorMessage = "Your records and preferences were reset, but some attachment or backup files could not be erased. Use Reset App Data again to retry cleanup." }
        } catch { errorMessage = error.localizedDescription }
    }
    func enableNotifications(documents: Bool, enabled: Bool) async {
        if documents { documentPermissionRevision += 1 } else { customPermissionRevision += 1 }
        let request = documents ? documentPermissionRevision : customPermissionRevision
        if enabled {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                guard request == (documents ? documentPermissionRevision : customPermissionRevision) else { return }
                guard granted else { errorMessage = "Notifications are disabled. Allow notifications for Vehicle Docs Vault in iOS Settings to receive reminders."; return }
            } catch { errorMessage = error.localizedDescription; return }
        }
        guard request == (documents ? documentPermissionRevision : customPermissionRevision) else { return }
        updatePreferences { if documents { $0.documentNotifications = enabled } else { $0.customNotifications = enabled } }
    }
    func refreshClock() {
        objectWillChange.send()
        if lastClockDay != Date().vaultDay { lastClockDay = Date().vaultDay; Task { await scheduleNotifications() } }
    }
    func scheduleNotifications() async {
        if schedulingNotifications { notificationNeedsRefresh = true; return }
        schedulingNotifications = true
        defer { schedulingNotifications = false }
        repeat {
        notificationNeedsRefresh = false
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let permission = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(permission.authorizationStatus) else { return }
        var candidates: [(String, String, String, Date)] = []
        let active = Set(activeVehicles.map(\.id))
        for record in database.records where !record.archived && active.contains(record.vehicleID) {
            if record.kind == .document, preferences.documentNotifications, let expiry = record.expiration,
               let day = Calendar.current.date(byAdding: .day, value: -preferences.expirationLead, to: expiry),
               let date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day), date > Date() {
                candidates.append((record.id.uuidString, record.title, "\(vehicle(record.vehicleID)?.title ?? "Vehicle") · Expires \(self.date(expiry))", date))
            }
            if record.kind == .reminder, preferences.customNotifications, !record.completed {
                let dates = VaultRecurrence.futureDates(for: record, after: Date(), count: 6)
                for (index, due) in dates.enumerated() { candidates.append(("\(record.id)-\(index)", record.title, vehicle(record.vehicleID)?.title ?? "Vehicle reminder", due)) }
            }
        }
        for item in candidates.sorted(by: { $0.3 < $1.3 }).prefix(64) {
            if notificationNeedsRefresh { break }
            let content = UNMutableNotificationContent()
            content.title = item.1; content.body = item.2; content.sound = .default
            content.userInfo = ["recordID": String(item.0.prefix(36))]
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.3)
            do { try await center.add(UNNotificationRequest(identifier: item.0, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))) }
            catch { errorMessage = "A reminder could not be scheduled. \(error.localizedDescription)"; break }
        }
        } while notificationNeedsRefresh
    }
    func changeDistanceUnit(_ unit: String) {
        guard unit != preferences.unit else { return }
        let target = unit == "Miles" ? "mi" : "km"
        let oldDefault = distanceSuffix
        commit { db in
            func converted(_ text: String, from: String) -> String {
                guard !text.isEmpty, from != target, let number = Double(text) else { return text }
                let result = target == "mi" ? number / 1.609344 : number * 1.609344
                return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), result)
            }
            for index in db.vehicles.indices {
                let from = db.vehicles[index]["distanceUnit"].isEmpty ? oldDefault : db.vehicles[index]["distanceUnit"]
                db.vehicles[index]["mileage"] = converted(db.vehicles[index]["mileage"], from: from)
                db.vehicles[index]["distanceUnit"] = target
            }
            for index in db.records.indices {
                let from = db.records[index]["distanceUnit"].isEmpty ? oldDefault : db.records[index]["distanceUnit"]
                db.records[index]["mileage"] = converted(db.records[index]["mileage"], from: from)
                db.records[index]["distanceUnit"] = target
            }
            db.preferences.unit = unit
        }
    }

}

struct VaultExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
