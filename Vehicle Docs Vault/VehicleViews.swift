import SwiftUI

struct VehiclesView: View {
    @EnvironmentObject var store: VaultStore
    @State private var search = ""
    @State private var sort = "Name"
    @State private var adding = false
    var vehicles: [Vehicle] {
        store.activeVehicles.filter { search.isEmpty || [$0.title, $0.make, $0.model, $0.plate, $0["vin"]].joined(separator: " ").localizedCaseInsensitiveContains(search) }.sorted {
            switch sort {
            case "Year": return $0.year > $1.year
            case "Recently Added": return $0.created > $1.created
            default: return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                VaultPageHeading(eyebrow: "Your private garage", title: "A collection\nworth keeping.", subtitle: "Every vehicle. Its own story.")
                VaultSearchField(text: $search, placeholder: "Name, plate or VIN")
                HStack {
                    Text("\(vehicles.count) VEHICLE\(vehicles.count == 1 ? "" : "S")").font(.vaultEyebrow).tracking(1.7).foregroundStyle(.secondary)
                    Spacer()
                    Menu { Picker("Sort", selection: $sort) { ForEach(["Name", "Year", "Recently Added"], id: \.self) { Text($0) } } } label: { Label(sort, systemImage: "arrow.up.arrow.down").font(.system(size: 11)).foregroundStyle(Color.vaultGold) }
                }
                if vehicles.isEmpty { EmptyVault(symbol: "car.side", title: search.isEmpty ? "Your collection begins here." : "No matching vehicles", message: search.isEmpty ? "Give every vehicle a beautifully organized home." : "Try another name, plate or VIN.", actionTitle: search.isEmpty ? "Add Vehicle" : "Clear Search", action: { if search.isEmpty { adding = true } else { search = "" } }) }
                LazyVStack(spacing: 26) {
                    ForEach(vehicles) { vehicle in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(vehicle.type.uppercased()).font(.vaultEyebrow).tracking(1.5).foregroundStyle(.secondary)
                                Spacer()
                                if store.selectedVehicle?.id == vehicle.id { Label("CURRENT VEHICLE", systemImage: "checkmark.circle.fill").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Color.vaultGold) }
                                else { Button("Make current") { store.selectVehicle(vehicle.id) }.font(.system(size: 11, weight: .medium)).foregroundStyle(Color.vaultGold) }
                            }
                            NavigationLink { VehicleDetail(vehicleID: vehicle.id) } label: { VehicleShowcaseCard(vehicle: vehicle, compact: true) }.buttonStyle(.plain)
                                .contextMenu { Button("Make Current Vehicle") { store.selectVehicle(vehicle.id) }; Button("Archive Vehicle") { store.setArchived(vehicle: vehicle, archived: true) } }
                        }
                    }
                }
            }.padding(22).frame(maxWidth: 850).frame(maxWidth: .infinity)
        }.background(Color.vaultBackground).navigationTitle("Garage").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button { adding = true } label: { Image(systemName: "plus").foregroundStyle(Color.vaultGold) }.accessibilityLabel("Add vehicle") }
            .sheet(isPresented: $adding) { NavigationStack { VehicleEditor() } }
    }
}

struct VehicleEditor: View {
    @EnvironmentObject var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    @State private var vehicle: Vehicle
    @State private var originalVehicle: Vehicle
    @State private var purchaseDate: Bool
    @State private var pending: [PendingAttachment] = []
    @State private var saving = false
    @State private var loadingAttachments = false
    @State private var discardChanges = false
    private let editing: Bool
    init(vehicle: Vehicle? = nil) {
        let initial = vehicle ?? Vehicle()
        _vehicle = State(initialValue: initial)
        _originalVehicle = State(initialValue: initial)
        _purchaseDate = State(initialValue: vehicle?.purchaseDate != nil)
        editing = vehicle != nil
    }
    var valid: Bool { VaultIntegrity.vehicleIssue(vehicle) == nil }
    var hasChanges: Bool { vehicle != originalVehicle || purchaseDate != (originalVehicle.purchaseDate != nil) || !pending.isEmpty || loadingAttachments }
    var mileageUnit: String { vehicle["distanceUnit"].isEmpty ? store.distanceSuffix : vehicle["distanceUnit"] }
    var body: some View {
        Form {
            Section {
                VaultEditorHeading(title: editing ? "A profile, perfected." : "Welcome to the collection.", subtitle: "Give this vehicle its own place. Start with a name and add the details that matter to you.", symbol: "car.side")
            }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section("Basic Information") {
                TextField("Vehicle Name *", text: $vehicle.name)
                TextField("Make", text: $vehicle.make)
                TextField("Model", text: $vehicle.model)
                TextField("Year", text: $vehicle.year).keyboardType(.numberPad)
                Picker("Vehicle Type", selection: $vehicle.type) { ForEach(["Car", "Motorcycle", "Van", "Truck", "Other"], id: \.self) { Text($0) } }
                field("Color", "color")
            }
            Section("Identification") {
                field("VIN", "vin", capitalized: true)
                TextField("License Plate", text: $vehicle.plate).textInputAutocapitalization(.characters).autocorrectionDisabled()
                field("Registration Number", "registrationNumber", capitalized: true)
            }
            Section("Technical") {
                field("Engine / Engine Code", "engine")
                field("Engine Size", "engineSize")
                options("Fuel Type", "fuel", ["Gasoline", "Diesel", "Hybrid", "Electric", "LPG", "Other"])
                options("Transmission", "transmission", ["Automatic", "Manual", "CVT", "Other"])
                options("Drive Type", "drive", ["FWD", "RWD", "AWD", "4WD", "Other"])
                field("Body Style", "body")
                field("Number of Doors", "doors", numeric: true)
                field("Factory Tire Specification", "tireSpecification")
                field("Factory Notes", "factoryNotes")
            }
            Section("Ownership & Mileage") {
                HStack { field("Current Mileage", "mileage", numeric: true); Text(mileageUnit).foregroundStyle(.secondary) }
                Toggle("Purchase Date", isOn: $purchaseDate)
                if purchaseDate { DatePicker("Purchased", selection: Binding(get: { vehicle.purchaseDate ?? Date() }, set: { vehicle.purchaseDate = $0 }), displayedComponents: .date) }
                TextField("Notes", text: value("notes"), axis: .vertical).lineLimit(3...8)
            }
            Section("Vehicle Photos") {
                PendingAttachmentsPicker(pending: $pending, imagesOnly: true, loading: $loadingAttachments)
                if editing { NavigationLink("Manage Existing Photos") { VehicleGallery(vehicleID: vehicle.id) }.disabled(loadingAttachments || saving) }
            }
            Section {
                Button { save() } label: { HStack { Spacer(); if saving { ProgressView() }; Text(editing ? "Save Changes" : "Create Vehicle").fontWeight(.semibold); Spacer() } }.buttonStyle(VaultPrimaryButton()).listRowInsets(EdgeInsets()).listRowBackground(Color.clear).disabled(!valid || saving || loadingAttachments)
            } footer: { if !valid { Text(VaultIntegrity.vehicleIssue(vehicle) ?? "") } }
        }.disabled(saving).vaultEditorSafety(hasChanges: hasChanges, isBusy: saving, confirmDiscard: $discardChanges).vaultListAppearance().navigationTitle(editing ? "Edit Vehicle" : "Add Vehicle").navigationBarTitleDisplayMode(.inline).vaultErrorBanner()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if hasChanges { discardChanges = true } else { dismiss() } }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!valid || saving || loadingAttachments) }
            }
    }
    func value(_ key: String) -> Binding<String> { Binding(get: { vehicle[key] }, set: { vehicle[key] = $0 }) }
    func field(_ title: String, _ key: String, capitalized: Bool = false, numeric: Bool = false) -> some View {
        TextField(title, text: value(key)).keyboardType(numeric ? (key == "doors" ? .numberPad : .decimalPad) : .default).textInputAutocapitalization(capitalized ? .characters : .sentences).autocorrectionDisabled(capitalized)
    }
    func options(_ title: String, _ key: String, _ choices: [String]) -> some View {
        Picker(title, selection: value(key)) { Text("Not specified").tag(""); ForEach(choices, id: \.self) { Text($0).tag($0) } }
    }
    func save() {
        guard valid, !saving, !loadingAttachments else { return }
        saving = true
        vehicle.name = vehicle.name.trimmingCharacters(in: .whitespacesAndNewlines)
        vehicle["vin"] = vehicle["vin"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        vehicle.plate = vehicle.plate.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        vehicle.purchaseDate = purchaseDate ? (vehicle.purchaseDate ?? Date()) : nil
        if !vehicle["mileage"].isEmpty { vehicle["distanceUnit"] = mileageUnit }
        if editing, let latest = store.vehicle(vehicle.id) { vehicle.coverID = latest.coverID }
        Task {
            guard await store.saveVehicle(vehicle, pending: pending) else { saving = false; return }
            pending = []
            dismiss()
        }
    }
}

struct VehicleDetail: View {
    @EnvironmentObject var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    var vehicleID: UUID
    @State private var editing = false
    @State private var deleting = false
    var vehicle: Vehicle? { store.vehicle(vehicleID) }
    var body: some View {
        Group {
            if let vehicle {
                List {
                    Section {
                        NavigationLink { VehicleGallery(vehicleID: vehicle.id) } label: { VehicleShowcaseCard(vehicle: vehicle) }.buttonStyle(.plain)
                            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                        if store.selectedVehicle?.id != vehicle.id && !vehicle.archived { Button("Make Current Vehicle") { store.selectVehicle(vehicle.id) } }
                    }
                    Section { MileageHistoryCard(vehicle: vehicle).listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                    Section { DocumentStatusCard(vehicleID: vehicle.id).listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                    Section("Basic Information") {
                        InfoLine(title: "Vehicle Type", value: vehicle.type)
                        InfoLine(title: "Color", value: vehicle["color"])
                        InfoLine(title: "Make", value: vehicle.make)
                        InfoLine(title: "Model", value: vehicle.model)
                        InfoLine(title: "Year", value: vehicle.year)
                    }
                    Section("Identification") {
                        InfoLine(title: "VIN", value: vehicle["vin"])
                        InfoLine(title: "Plate", value: vehicle.plate)
                        InfoLine(title: "Registration", value: vehicle["registrationNumber"])
                        if vehicle["vin"].isEmpty && vehicle.plate.isEmpty && vehicle["registrationNumber"].isEmpty { Text("No identification details added").foregroundStyle(.secondary) }
                    }
                    Section("Technical Details") {
                        InfoLine(title: "Engine", value: vehicle["engine"])
                        InfoLine(title: "Engine Size", value: vehicle["engineSize"])
                        InfoLine(title: "Fuel", value: vehicle["fuel"])
                        InfoLine(title: "Transmission", value: vehicle["transmission"])
                        InfoLine(title: "Drive Type", value: vehicle["drive"])
                        NavigationLink("All Technical Information") { TechnicalInformation(vehicleID: vehicle.id) }
                    }
                    Section("Ownership Information") {
                        InfoLine(title: "Purchased", value: vehicle.purchaseDate.map(store.date) ?? "Not specified")
                        InfoLine(title: "Mileage", value: vehicle["mileage"].isEmpty ? "Not specified" : "\(vehicle["mileage"]) \(vehicle["distanceUnit"].isEmpty ? store.distanceSuffix : vehicle["distanceUnit"])")
                        if !vehicle["notes"].isEmpty { Text(vehicle["notes"]).textSelection(.enabled) }
                    }
                    Section("Vehicle Records") {
                        ForEach([RecordKind.document, .part, .tire, .replacement, .tireChange, .note, .reminder]) { kind in
                            NavigationLink { RecordsList(kind: kind, vehicleID: vehicle.id) } label: { HStack { Label(kind.plural, systemImage: kind.symbol); Spacer(); Text("\(store.records(kind, vehicleID: vehicle.id).count)").foregroundStyle(.secondary) } }
                        }
                        NavigationLink { VehicleGallery(vehicleID: vehicle.id) } label: { Label("Photo Gallery", systemImage: "photo.on.rectangle") }
                        NavigationLink { TimelineView(vehicleID: vehicle.id) } label: { Label("Timeline", systemImage: "clock.arrow.circlepath") }
                    }
                    Section {
                        Button(vehicle.archived ? "Restore Vehicle" : "Archive Vehicle") { if store.setArchived(vehicle: vehicle, archived: !vehicle.archived) { dismiss() } }
                        Button("Delete Vehicle", role: .destructive) { deleting = true }
                    }
                }
            } else { EmptyVault(symbol: "car.side", title: "Vehicle unavailable", message: "This vehicle may have been removed.") }
        }.vaultListAppearance().navigationTitle("Vehicle Details").navigationBarTitleDisplayMode(.inline)
            .toolbar { if vehicle != nil { Button("Edit") { editing = true } } }
            .sheet(isPresented: $editing) { if let vehicle { NavigationStack { VehicleEditor(vehicle: vehicle) } } }
            .confirmationDialog("Delete this vehicle and all its records and attachments?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete Vehicle", role: .destructive) { if store.deleteVehicle(vehicleID) { dismiss() } }
            }
    }
}

struct TechnicalInformation: View {
    @EnvironmentObject var store: VaultStore
    var vehicleID: UUID
    @State private var editing = false
    var body: some View {
        List {
            if let vehicle = store.vehicle(vehicleID) {
                Section("Identification") {
                    InfoLine(title: "VIN", value: vehicle["vin"].isEmpty ? "Not specified" : vehicle["vin"])
                    InfoLine(title: "Registration Number", value: vehicle["registrationNumber"])
                    InfoLine(title: "License Plate", value: vehicle.plate)
                }
                Section("Engine & Transmission") {
                    InfoLine(title: "Engine Code", value: vehicle["engine"])
                    InfoLine(title: "Displacement", value: vehicle["engineSize"])
                    InfoLine(title: "Fuel Type", value: vehicle["fuel"])
                    InfoLine(title: "Transmission", value: vehicle["transmission"])
                }
                Section("Vehicle") {
                    InfoLine(title: "Drive Type", value: vehicle["drive"])
                    InfoLine(title: "Body Style", value: vehicle["body"])
                    InfoLine(title: "Doors", value: vehicle["doors"])
                    InfoLine(title: "Color", value: vehicle["color"])
                    InfoLine(title: "Tire Specification", value: vehicle["tireSpecification"])
                    InfoLine(title: "Factory Notes", value: vehicle["factoryNotes"])
                }
                Button("Edit Technical Information") { editing = true }
            } else { EmptyVault(symbol: "car.side", title: "Vehicle unavailable", message: "This vehicle may have been removed.") }
        }.vaultListAppearance().navigationTitle("Technical Information").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $editing) { if let vehicle = store.vehicle(vehicleID) { NavigationStack { VehicleEditor(vehicle: vehicle) } } }
    }
}
