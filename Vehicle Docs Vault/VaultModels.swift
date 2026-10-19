import Foundation
import SwiftUI

struct Vehicle: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name = ""
    var make = ""
    var model = ""
    var year = ""
    var plate = ""
    var type = "Car"
    var values: [String: String] = [:]
    var purchaseDate: Date?
    var coverID: UUID?
    var created = Date()
    var archived = false
    var title: String { name.isEmpty ? [make, model].filter { !$0.isEmpty }.joined(separator: " ") : name }
    var subtitle: String { [year, make, model].filter { !$0.isEmpty }.joined(separator: " · ") }
    subscript(_ key: String) -> String {
        get { values[key, default: ""] }
        set { values[key] = newValue }
    }
}

enum RecordKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case document, part, replacement, tire, tireChange, note, reminder
    var id: String { rawValue }
    var title: String {
        switch self {
        case .document: return "Document"
        case .part: return "Part"
        case .replacement: return "Replacement"
        case .tire: return "Tire Set"
        case .tireChange: return "Tire Change"
        case .note: return "Note"
        case .reminder: return "Reminder"
        }
    }
    var plural: String {
        switch self {
        case .replacement: return "Replacements"
        case .tire: return "Tire Sets"
        case .tireChange: return "Tire Changes"
        default: return title + "s"
        }
    }
    var symbol: String {
        switch self {
        case .document: return "doc.text"
        case .part: return "gearshape.2"
        case .replacement: return "wrench.and.screwdriver"
        case .tire: return "circle.circle"
        case .tireChange: return "arrow.triangle.2.circlepath"
        case .note: return "note.text"
        case .reminder: return "bell"
        }
    }
    var categories: [String] {
        switch self {
        case .document: return ["Registration", "Insurance", "Inspection", "Ownership", "Tax", "Warranty", "Other"]
        case .part, .replacement: return ["Engine", "Filters", "Brakes", "Battery", "Lights", "Tires", "Suspension", "Fluids", "Electrical", "Interior", "Exterior", "Other"]
        case .note: return ["General", "Technical", "Parts", "Documents", "Tires", "Other"]
        case .tire: return ["Summer", "Winter", "All Season"]
        default: return []
        }
    }
    var emptyTitle: String {
        switch self {
        case .document: return "No documents yet"
        case .part: return "No parts added"
        case .tire: return "No tire sets added"
        case .note: return "No notes yet"
        case .reminder: return "No upcoming reminders"
        case .replacement: return "Every replacement, recorded"
        case .tireChange: return "No tire changes yet"
        }
    }
    var tint: Color {
        switch self {
        case .document: return .blue
        case .part, .replacement: return .orange
        case .tire, .tireChange: return .teal
        case .note: return .purple
        case .reminder: return .indigo
        }
    }
}

struct VaultRecord: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var vehicleID: UUID
    var kind: RecordKind
    var title = ""
    var category = ""
    var status = ""
    var date = Date()
    var expiration: Date?
    var created = Date()
    var notes = ""
    var fields: [String: String] = [:]
    var archived = false
    var completed = false
    subscript(_ key: String) -> String {
        get { fields[key, default: ""] }
        set { fields[key] = newValue }
    }
    var displayTitle: String {
        if !title.isEmpty { return title }
        return kind.title
    }
    var computedStatus: String {
        if archived { return "Archived" }
        if kind == .document {
            guard let expiration else { return "No Expiration" }
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: expiration)).day ?? 0
            return days < 0 ? "Expired" : days <= 30 ? "Expiring Soon" : "Active"
        }
        if kind == .reminder { return completed ? "Completed" : date < Date() ? "Past" : "Upcoming" }
        return status
    }
    var tireSize: String { "\(self["width"])/\(self["ratio"]) R\(self["rim"])" }
    var searchable: String { ([title, category, notes, status] + Array(fields.values)).joined(separator: " ") }
}

struct VaultAttachment: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var vehicleID: UUID
    var ownerID: UUID
    var name: String
    var fileName: String
    var category: String
    var added = Date()
    var byteCount: Int
    var isPDF: Bool { fileName.lowercased().hasSuffix(".pdf") }
}

struct VaultEvent: Identifiable, Codable, Sendable {
    var id = UUID()
    var vehicleID: UUID
    var targetID: UUID
    var kind: RecordKind?
    var title: String
    var date = Date()
}

struct VaultPreferences: Codable, Sendable {
    var appearance = "System"
    var unit = "Kilometers"
    var dateFormat = "DD/MM/YYYY"
    var defaultVehicleID: UUID?
    var documentNotifications = false
    var customNotifications = false
    var expirationLead = 7
    var onboarded = false
}

struct VaultDatabase: Codable, Sendable {
    var schemaVersion = 1
    var clientID = UUID()
    var vehicles: [Vehicle] = []
    var records: [VaultRecord] = []
    var attachments: [VaultAttachment] = []
    var events: [VaultEvent] = []
    var preferences = VaultPreferences()
    var selectedVehicleID: UUID?
    var recentSearches: [String] = []
}

struct BackupEnvelope: Codable, Sendable {
    var format = "VehicleDocsVault"
    var version = 1
    var created = Date()
    var database: VaultDatabase
    var files: [String: Data]
}

struct LocalBackup: Identifiable, Sendable {
    var url: URL
    var date: Date
    var size: Int
    var id: String { url.lastPathComponent }
}

enum VaultError: LocalizedError {
    case invalidFile, missingFile, incompatibleVersion, invalidReference, noData, transferTooLarge
    var errorDescription: String? {
        switch self {
        case .invalidFile: return "This file is not a valid Vehicle Docs Vault backup."
        case .missingFile: return "An attachment is missing. The operation was stopped to keep your data intact."
        case .incompatibleVersion: return "This backup was created by a newer version of the app."
        case .invalidReference: return "The file contains duplicate identifiers or incomplete record relationships."
        case .noData: return "Select at least one category to export."
        case .transferTooLarge: return "This export exceeds the 512 MB transfer limit. Export fewer categories or remove large attachments before trying again."
        }
    }
}

extension Date {
    var vaultDay: Date { Calendar.current.startOfDay(for: self) }
}

extension Date {
    var vaultTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

enum VaultFormatting {
    static func fileSize(_ bytes: Int) -> String {
        var size = Double(bytes)
        let units = ["B", "KB", "MB", "GB"]
        var index = 0
        while size >= 1024 && index < units.count - 1 { size /= 1024; index += 1 }
        return index == 0 ? "\(bytes) B" : String(format: "%.1f %@", locale: Locale(identifier: "en_US_POSIX"), size, units[index])
    }
}
