import Foundation

struct PendingAttachment: Identifiable, Sendable {
    var id = UUID()
    var name: String
    var ext: String
    var data: Data
}

struct VaultValidationError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

enum VaultNumbers {
    static func decimal(_ text: String) -> Double? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
        if value.range(of: #"^\d{1,3}(,\d{3})+(\.\d+)?$"#, options: .regularExpression) != nil { value = value.replacingOccurrences(of: ",", with: "") }
        else if !value.contains(".") { value = value.replacingOccurrences(of: ",", with: ".") }
        guard let number = Double(value), number.isFinite, number >= 0, number <= 1_000_000_000_000 else { return nil }
        return number
    }
    static func canonical(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 3
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }
}

enum VaultRecurrence {
    static let choices = ["Never", "Monthly", "Every 3 Months", "Every 6 Months", "Yearly"]
    static func months(_ rule: String) -> Int? { ["Monthly": 1, "Every 3 Months": 3, "Every 6 Months": 6, "Yearly": 12][rule] }
    static func futureDates(for record: VaultRecord, after now: Date, count: Int) -> [Date] {
        guard let interval = months(record["recurrence"]) else { return record.date > now ? [record.date] : [] }
        let calendar = Calendar.current
        let anchor = ISO8601DateFormatter().date(from: record["recurrenceAnchor"]) ?? record.date
        let lowerBound = max(now, record.date.addingTimeInterval(-1))
        let difference = calendar.dateComponents([.month], from: anchor, to: lowerBound).month ?? 0
        var index = max(0, difference / interval)
        var result: [Date] = []
        for _ in 0..<(count + 24) {
            guard let date = calendar.date(byAdding: .month, value: index * interval, to: anchor) else { break }
            if date > lowerBound { result.append(date) }
            if result.count == count { break }
            index += 1
        }
        return result
    }
}

enum VaultIntegrity {
    static let supportedExtensions = Set(["pdf", "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff"])
    static let transferLimit = 512 * 1024 * 1024
    static func validFileName(_ name: String) -> Bool {
        let url = URL(fileURLWithPath: name)
        return name == url.lastPathComponent && !name.contains("/") && !name.contains("..")
            && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil && supportedExtensions.contains(url.pathExtension.lowercased())
    }
    static func vehicleIssue(_ vehicle: Vehicle) -> String? {
        if vehicle.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a vehicle name." }
        let maximum = Calendar(identifier: .gregorian).component(.year, from: Date()) + 2
        if !vehicle.year.isEmpty && !(1886...maximum).contains(Int(vehicle.year) ?? 0) { return "Enter a valid vehicle year." }
        if !vehicle["mileage"].isEmpty && VaultNumbers.decimal(vehicle["mileage"]) == nil { return "Enter a valid, nonnegative mileage." }
        if !vehicle["doors"].isEmpty && !(0...20).contains(Int(vehicle["doors"]) ?? -1) { return "Enter a whole number of doors from 0 to 20." }
        return nil
    }
    static func recordIssue(_ record: VaultRecord) -> String? {
        if record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a record name." }
        if !record["mileage"].isEmpty && VaultNumbers.decimal(record["mileage"]) == nil { return "Enter a valid, nonnegative mileage." }
        if record.kind == .part && (Int(record["quantity"]) ?? 0) < 1 { return "Quantity must be a whole number of at least 1." }
        if record.kind == .note && record.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter some note text." }
        if record.kind == .document, let expiration = record.expiration, expiration.vaultDay < record.date.vaultDay { return "Expiration must be on or after the issue date." }
        if record.kind == .tire {
            if record["manufacturer"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter the tire manufacturer." }
            if !(100...500).contains(Int(record["width"]) ?? 0) || !(15...100).contains(Int(record["ratio"]) ?? 0) || !(8...36).contains(Int(record["rim"]) ?? 0) { return "Enter a tire width from 100 to 500, aspect ratio from 15 to 100, and rim size from 8 to 36." }
            let maximum = Calendar(identifier: .gregorian).component(.year, from: Date()) + 2
            if !record["productionYear"].isEmpty && !(1900...maximum).contains(Int(record["productionYear"]) ?? 0) { return "Enter a valid tire production year." }
        }
        if [.replacement, .tireChange].contains(record.kind) {
            if !record["installedID"].isEmpty && record["installedID"] == record["removedID"] { return "Installed and removed items must be different." }
            if record.kind == .tireChange && record["installedID"].isEmpty && record["installedName"].isEmpty { return "Select the installed tire set." }
            if record.date.vaultDay > Date().vaultDay { return "A historical change cannot be in the future. Use a reminder to plan a future change." }
        }
        if record.kind == .part && !["Installed", "Stored", "Removed"].contains(record.status) { return "Select a part status." }
        if record.kind == .tire && !["Installed", "Stored", "Retired"].contains(record.status) { return "Select a tire set status." }
        if !record.kind.categories.isEmpty && !record.kind.categories.contains(record.category) { return "Select a category." }
        if record.kind == .reminder && !VaultRecurrence.choices.contains(record["recurrence"].isEmpty ? "Never" : record["recurrence"]) { return "Select a valid repeat rule." }
        return nil
    }
    static func normalizeNavigation(_ input: VaultDatabase) -> VaultDatabase {
        var db = input
        let active = db.vehicles.filter { !$0.archived }
        if !active.contains(where: { $0.id == db.preferences.defaultVehicleID }) { db.preferences.defaultVehicleID = active.first?.id }
        if !active.contains(where: { $0.id == db.selectedVehicleID }) { db.selectedVehicleID = db.preferences.defaultVehicleID ?? active.first?.id }
        for index in db.vehicles.indices {
            if let id = db.vehicles[index].coverID, !db.attachments.contains(where: { $0.id == id && $0.ownerID == db.vehicles[index].id && $0.vehicleID == db.vehicles[index].id && !$0.isPDF }) { db.vehicles[index].coverID = nil }
        }
        return db
    }
    static func validateDatabase(_ db: VaultDatabase) throws {
        guard db.schemaVersion == 1 else { throw VaultError.incompatibleVersion }
        let vehicles = Set(db.vehicles.map(\.id)), records = Set(db.records.map(\.id)), attachments = Set(db.attachments.map(\.id))
        guard vehicles.count == db.vehicles.count, records.count == db.records.count, attachments.count == db.attachments.count,
              Set(db.events.map(\.id)).count == db.events.count, vehicles.isDisjoint(with: records), attachments.isDisjoint(with: vehicles.union(records)),
              Set(db.attachments.map(\.fileName)).count == db.attachments.count else { throw VaultError.invalidReference }
        let recordsByID = Dictionary(uniqueKeysWithValues: db.records.map { ($0.id, $0) })
        let filesByID = Dictionary(uniqueKeysWithValues: db.attachments.map { ($0.id, $0) })
        for vehicle in db.vehicles {
            guard !vehicle.title.isEmpty else { throw VaultError.invalidReference }
            if let coverID = vehicle.coverID {
                guard let file = filesByID[coverID], file.vehicleID == vehicle.id, file.ownerID == vehicle.id, !file.isPDF else { throw VaultError.invalidReference }
            }
        }
        for record in db.records {
            guard vehicles.contains(record.vehicleID), !record.title.isEmpty else { throw VaultError.invalidReference }
            for key in ["installedID", "removedID", "relatedID"] where !record[key].isEmpty {
                guard let id = UUID(uuidString: record[key]), id != record.id, let linked = recordsByID[id], linked.vehicleID == record.vehicleID else { throw VaultError.invalidReference }
                if key != "relatedID" {
                    guard (record.kind == .replacement && linked.kind == .part) || (record.kind == .tireChange && linked.kind == .tire) else { throw VaultError.invalidReference }
                }
            }
        }
        for file in db.attachments {
            guard validFileName(file.fileName), file.byteCount > 0, file.byteCount <= 50_000_000, !file.name.isEmpty, vehicles.contains(file.vehicleID),
                  file.ownerID == file.vehicleID || recordsByID[file.ownerID]?.vehicleID == file.vehicleID else { throw VaultError.invalidReference }
        }
        guard db.events.allSatisfy({ vehicles.contains($0.vehicleID) }), ["System", "Light", "Dark"].contains(db.preferences.appearance),
              ["Kilometers", "Miles"].contains(db.preferences.unit), ["DD/MM/YYYY", "MM/DD/YYYY", "YYYY/MM/DD"].contains(db.preferences.dateFormat),
              [0, 1, 3, 7, 30].contains(db.preferences.expirationLead) else { throw VaultError.invalidFile }
    }
    static func validateEnvelope(_ envelope: BackupEnvelope) throws {
        guard envelope.format == "VehicleDocsVault" else { throw VaultError.invalidFile }
        guard envelope.version == 1 else { throw VaultError.incompatibleVersion }
        try validateDatabase(envelope.database)
        guard Set(envelope.files.keys) == Set(envelope.database.attachments.map(\.fileName)) else { throw VaultError.invalidReference }
        for file in envelope.database.attachments {
            guard envelope.files[file.fileName]?.count == file.byteCount else { throw VaultError.missingFile }
        }
    }
}

enum VaultErrors {
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let value = error as NSError
        return (value.domain == NSCocoaErrorDomain && value.code == NSUserCancelledError) || (value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled)
    }
}
