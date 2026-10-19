import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum VaultCodec {
    static func encoder() -> JSONEncoder {
        let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; value.outputFormatting = [.prettyPrinted, .sortedKeys]; return value
    }
    static func decoder() -> JSONDecoder {
        let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value
    }
}

struct StagedVaultRestore: Sendable {
    var database: VaultDatabase
    var files: [URL]
}

actor VaultTransfer {
    static let shared = VaultTransfer()
    private let fm = FileManager.default

    static func validateMedia(_ data: Data, ext: String) throws {
        guard !data.isEmpty, data.count <= 50_000_000 else { throw VaultValidationError(message: "Choose a nonempty file smaller than 50 MB.") }
        if ext.lowercased() == "pdf" {
            guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else { throw VaultValidationError(message: "This PDF could not be opened. Choose a valid PDF file.") }
            guard !pdf.isLocked else { throw VaultValidationError(message: "This PDF is password protected. Add an unlocked copy.") }
        } else {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { throw VaultValidationError(message: "This image could not be opened. Choose a valid image file.") }
        }
    }
    func prepareAttachment(_ data: Data, name: String, ext: String) throws -> PendingAttachment {
        try Task.checkCancellation()
        let isPDF = ext.lowercased() == "pdf" || data.starts(with: Data("%PDF-".utf8))
        try Self.validateMedia(data, ext: isPDF ? "pdf" : ext)
        if isPDF { return PendingAttachment(name: name, ext: "pdf", data: data) }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let identifier = CGImageSourceGetType(source) else { throw VaultError.invalidFile }
        var actualExtension = UTType(identifier as String)?.preferredFilenameExtension?.lowercased() ?? ""
        if actualExtension == "tif" { actualExtension = "tiff" }
        if VaultIntegrity.supportedExtensions.contains(actualExtension) {
            return PendingAttachment(name: name, ext: actualExtension, data: data)
        }
        // Convert formats such as WebP off the main thread, including orientation.
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096
        ] as CFDictionary) else { throw VaultValidationError(message: "This image could not be opened. Choose a different image file.") }
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil) else { throw VaultError.invalidFile }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw VaultError.invalidFile }
        let converted = bytes as Data
        try Self.validateMedia(converted, ext: "png")
        return PendingAttachment(name: name, ext: "png", data: converted)
    }
    func stageAttachments(_ drafts: [PendingAttachment], directory: URL, vehicleID: UUID, ownerID: UUID, category: String) throws -> [VaultAttachment] {
        var staged: [VaultAttachment] = []
        do {
            for draft in drafts {
                try Task.checkCancellation()
                guard VaultIntegrity.supportedExtensions.contains(draft.ext.lowercased()) else { throw VaultError.invalidFile }
                try Self.validateMedia(draft.data, ext: draft.ext)
                let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { throw VaultValidationError(message: "Enter an attachment name.") }
                let file = VaultAttachment(vehicleID: vehicleID, ownerID: ownerID, name: name, fileName: UUID().uuidString + "." + draft.ext.lowercased(), category: category, byteCount: draft.data.count)
                try draft.data.write(to: directory.appendingPathComponent(file.fileName), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                staged.append(file)
            }
            return staged
        } catch {
            for file in staged { try? fm.removeItem(at: directory.appendingPathComponent(file.fileName)) }
            throw error
        }
    }
    func envelope(database: VaultDatabase, directory: URL, kinds: Set<RecordKind>, includeVehicles: Bool) throws -> BackupEnvelope {
        guard !kinds.isEmpty || includeVehicles else { throw VaultError.noData }
        var exported = database
        var recordIDs = Set(database.records.filter { kinds.contains($0.kind) }.map(\.id))
        let byID = Dictionary(uniqueKeysWithValues: database.records.map { ($0.id, $0) })
        var pending = Array(recordIDs)
        while let id = pending.popLast(), let record = byID[id] {
            for key in ["installedID", "removedID", "relatedID"] {
                if let reference = UUID(uuidString: record[key]), recordIDs.insert(reference).inserted { pending.append(reference) }
            }
        }
        exported.records = database.records.filter { recordIDs.contains($0.id) }
        let usedVehicles = Set(exported.records.map(\.vehicleID))
        exported.vehicles = database.vehicles.filter { includeVehicles || usedVehicles.contains($0.id) }
        let vehicleIDs = Set(exported.vehicles.map(\.id))
        let ownerIDs = recordIDs.union(vehicleIDs)
        exported.attachments = database.attachments.filter { ownerIDs.contains($0.ownerID) }
        exported.events = database.events.filter { ownerIDs.contains($0.targetID) }
        if let id = exported.selectedVehicleID, !vehicleIDs.contains(id) { exported.selectedVehicleID = exported.vehicles.first(where: { !$0.archived })?.id }
        if let id = exported.preferences.defaultVehicleID, !vehicleIDs.contains(id) { exported.preferences.defaultVehicleID = exported.vehicles.first(where: { !$0.archived })?.id }
        var files: [String: Data] = [:]
        var size = 0
        for file in exported.attachments {
            try Task.checkCancellation()
            guard VaultIntegrity.validFileName(file.fileName) else { throw VaultError.invalidFile }
            let url = directory.appendingPathComponent(file.fileName)
            guard fm.fileExists(atPath: url.path) else { throw VaultError.missingFile }
            size += file.byteCount
            guard size < VaultIntegrity.transferLimit * 3 / 4 else { throw VaultError.transferTooLarge }
            let bytes = try Data(contentsOf: url)
            guard bytes.count == file.byteCount else { throw VaultError.missingFile }
            files[file.fileName] = bytes
        }
        let value = BackupEnvelope(database: exported, files: files)
        try VaultIntegrity.validateEnvelope(value)
        return value
    }
    func export(database: VaultDatabase, directory: URL, kinds: Set<RecordKind>, vehicles: Bool, csv: Bool) throws -> Data {
        let data: Data
        if csv {
            var rows = [["Type", "ID", "Vehicle ID", "Title", "Category", "Status", "Date", "Expiration", "Notes", "Details JSON"]]
            let formatter = ISO8601DateFormatter()
            if vehicles {
                for vehicle in database.vehicles {
                    rows.append(["Vehicle", vehicle.id.uuidString, vehicle.id.uuidString, vehicle.title, vehicle.type, vehicle.archived ? "Archived" : "Active", formatter.string(from: vehicle.created), "", vehicle["notes"], String(decoding: try VaultCodec.encoder().encode(vehicle), as: UTF8.self)])
                }
            }
            for record in database.records where kinds.contains(record.kind) {
                rows.append([record.kind.title, record.id.uuidString, record.vehicleID.uuidString, record.title, record.category, record.computedStatus, formatter.string(from: record.date), record.expiration.map(formatter.string) ?? "", record.notes, String(decoding: try VaultCodec.encoder().encode(record), as: UTF8.self)])
            }
            data = Data(("\u{FEFF}" + rows.map { $0.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") }.joined(separator: "\r\n")).utf8)
        } else { data = try VaultCodec.encoder().encode(envelope(database: database, directory: directory, kinds: kinds, includeVehicles: vehicles)) }
        guard data.count <= VaultIntegrity.transferLimit else { throw VaultError.transferTooLarge }
        return data
    }
    private func coordinatedData(_ url: URL, limit: Int) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { source in
            result = Result {
                let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= limit else { throw VaultError.transferTooLarge }
                let file = try FileHandle(forReadingFrom: source)
                defer { try? file.close() }
                var bytes = Data()
                while let chunk = try file.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                    guard bytes.count + chunk.count <= limit else { throw VaultError.transferTooLarge }
                    bytes.append(chunk)
                }
                return bytes
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw VaultError.invalidFile }
        return try result.get()
    }
    func attachment(_ url: URL) throws -> PendingAttachment {
        let data: Data
        do { data = try coordinatedData(url, limit: 50_000_000) }
        catch VaultError.transferTooLarge { throw VaultValidationError(message: "Choose a file smaller than 50 MB.") }
        return try prepareAttachment(data, name: url.deletingPathExtension().lastPathComponent, ext: url.pathExtension)
    }
    func read(_ url: URL) throws -> BackupEnvelope {
        let bytes = try coordinatedData(url, limit: VaultIntegrity.transferLimit)
        var value = try VaultCodec.decoder().decode(BackupEnvelope.self, from: bytes)
        value.database = VaultIntegrity.normalizeNavigation(value.database)
        try VaultIntegrity.validateEnvelope(value)
        for file in value.database.attachments {
            guard let bytes = value.files[file.fileName] else { throw VaultError.missingFile }
            try Self.validateMedia(bytes, ext: URL(fileURLWithPath: file.fileName).pathExtension)
        }
        return value
    }
    func backup(database: VaultDatabase, attachments: URL, destination: URL) throws {
        let data = try export(database: database, directory: attachments, kinds: Set(RecordKind.allCases), vehicles: true, csv: false)
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func recoveryCopy(root: URL, destination: URL) throws {
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in ["vault.json", "Attachments"] {
            let source = root.appendingPathComponent(name)
            if fm.fileExists(atPath: source.path) { try fm.copyItem(at: source, to: destination.appendingPathComponent(name)) }
        }
    }
    func stageRestore(_ envelope: BackupEnvelope, directory: URL, clientID: UUID) throws -> StagedVaultRestore {
        try VaultIntegrity.validateEnvelope(envelope)
        var restored = envelope.database
        restored.clientID = clientID
        restored.preferences.documentNotifications = false
        restored.preferences.customNotifications = false
        var written: [URL] = []
        do {
            for index in restored.attachments.indices {
                try Task.checkCancellation()
                let old = restored.attachments[index]
                guard let bytes = envelope.files[old.fileName] else { throw VaultError.missingFile }
                try Self.validateMedia(bytes, ext: URL(fileURLWithPath: old.fileName).pathExtension)
                let name = UUID().uuidString + "." + URL(fileURLWithPath: old.fileName).pathExtension.lowercased()
                let url = directory.appendingPathComponent(name)
                try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                written.append(url)
                restored.attachments[index].fileName = name
            }
            return StagedVaultRestore(database: restored, files: written)
        } catch { for url in written { try? fm.removeItem(at: url) }; throw error }
    }
    func removeFiles(_ urls: [URL]) throws {
        var firstError: Error?
        for url in urls where fm.fileExists(atPath: url.path) {
            do { try fm.removeItem(at: url) } catch { if firstError == nil { firstError = error } }
        }
        if let firstError { throw firstError }
    }
    func cleanAttachments(directory: URL, keeping: Set<String>) throws {
        for url in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where !keeping.contains(url.lastPathComponent) {
            try fm.removeItem(at: url)
        }
    }
}
