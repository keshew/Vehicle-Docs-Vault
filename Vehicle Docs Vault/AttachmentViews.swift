import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import PDFKit
import UIKit

struct PendingAttachmentsPicker: View {
    @EnvironmentObject var store: VaultStore
    @Binding var pending: [PendingAttachment]
    var imagesOnly = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var importing = false
    @Binding var loading: Bool
    @State private var loadingTask: Task<Void, Never>?
    init(pending: Binding<[PendingAttachment]>, imagesOnly: Bool = false, loading: Binding<Bool>) {
        _pending = pending; self.imagesOnly = imagesOnly; _loading = loading
    }
    var body: some View {
        Group {
            PhotosPicker(selection: $photoItems, maxSelectionCount: 12, matching: .images) { Label("Add Image", systemImage: "photo.badge.plus") }.disabled(loading)
            if !imagesOnly { Button { importing = true } label: { Label("Add PDF or Image File", systemImage: "doc.badge.plus") }.disabled(loading) }
            if loading { HStack { ProgressView(); Text("Loading attachments…").font(.caption).foregroundStyle(.secondary) } }
            ForEach(pending) { item in
                HStack {
                    Image(systemName: item.ext == "pdf" ? "doc.richtext" : "photo").foregroundStyle(Color.vaultBlue)
                    Text(item.name).font(.subheadline).lineLimit(1)
                    Spacer()
                    Button(role: .destructive) { pending.removeAll { $0.id == item.id } } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless).accessibilityLabel("Remove \(item.name)")
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            do {
                let urls = try result.get()
                loading = true
                loadingTask = Task {
                    defer { loading = false }
                    for url in urls {
                        do {
                            let file = try await VaultTransfer.shared.attachment(url)
                            guard !Task.isCancelled else { return }
                            append(file)
                        } catch { if !Task.isCancelled && !VaultErrors.isCancellation(error) { store.errorMessage = error.localizedDescription } }
                    }
                }
            } catch { if !VaultErrors.isCancellation(error) { store.errorMessage = error.localizedDescription } }
        }
        .onChange(of: photoItems) { items in
            guard !items.isEmpty else { return }
            loading = true
            loadingTask = Task {
                defer { loading = false; photoItems = [] }
                for item in items {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw VaultValidationError(message: "This photo is unavailable. Download it to your device and try again.") }
                        guard !Task.isCancelled else { return }
                        let ext = item.supportedContentTypes.first(where: { $0.conforms(to: .image) })?.preferredFilenameExtension ?? "jpg"
                        let file = try await VaultTransfer.shared.prepareAttachment(data, name: "Photo \(pending.count + 1)", ext: ext)
                        guard !Task.isCancelled else { return }
                        append(file)
                    } catch { if !Task.isCancelled { store.errorMessage = "The photo could not be loaded. \(error.localizedDescription)" } }
                }
            }
        }
        .onDisappear { loadingTask?.cancel(); loading = false }
    }
    func append(_ file: PendingAttachment) {
        guard pending.reduce(0, { $0 + $1.data.count }) + file.data.count <= 128 * 1024 * 1024 else { store.errorMessage = "Add up to 128 MB of attachments at a time."; return }
        guard !imagesOnly || file.ext != "pdf" else { store.errorMessage = "Choose an image for the vehicle photo gallery."; return }
        pending.append(file)
    }
}

struct AttachmentLinks: View {
    @EnvironmentObject var store: VaultStore
    var ownerID: UUID
    var body: some View {
        let files = store.attachments(for: ownerID)
        if files.isEmpty { Text("No attachments. Use Edit to add images or PDFs.").font(.subheadline).foregroundStyle(.secondary) }
        ForEach(files) { item in
            NavigationLink { AttachmentDetail(attachmentID: item.id) } label: {
                HStack(spacing: 12) { Image(systemName: item.isPDF ? "doc.richtext" : "photo").foregroundStyle(Color.vaultBlue); VStack(alignment: .leading, spacing: 4) { Text(item.name).font(.subheadline); Text(VaultFormatting.fileSize(item.byteCount)).font(.caption).foregroundStyle(.secondary) } }
            }
        }
    }
}

struct VehicleGallery: View {
    @EnvironmentObject var store: VaultStore
    var vehicleID: UUID
    @State private var adding = false
    var photos: [VaultAttachment] { store.attachments(for: vehicleID).filter { !$0.isPDF } }
    var body: some View {
        ScrollView {
            if store.vehicle(vehicleID) == nil {
                EmptyVault(symbol: "car.side", title: "Vehicle unavailable", message: "This vehicle and its photo library have been removed.")
            } else if photos.isEmpty {
                EmptyVault(symbol: "photo.on.rectangle", title: "A view of your vehicle", message: "Add photos and choose one for your vehicle cover.", actionTitle: "Add Photo", action: { adding = true })
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 14)], spacing: 14) {
                    ForEach(photos) { photo in
                        NavigationLink { AttachmentDetail(attachmentID: photo.id) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                AttachmentThumbnail(item: photo).frame(height: 145).clipped().clipShape(RoundedRectangle(cornerRadius: 16))
                                HStack { Text(photo.name).font(.caption).lineLimit(1); if store.vehicle(vehicleID)?.coverID == photo.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.vaultBlue) } }.foregroundStyle(.primary)
                            }
                        }
                    }
                }.padding(20)
            }
        }.background(Color.vaultBackground).navigationTitle("Vehicle Photos")
            .toolbar { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add photo").disabled(store.vehicle(vehicleID) == nil) }
            .sheet(isPresented: $adding) { NavigationStack { AddAttachmentsView(vehicleID: vehicleID, ownerID: vehicleID, category: "Vehicle Photos", imagesOnly: true) } }
    }
}

struct AddAttachmentsView: View {
    @EnvironmentObject var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    var vehicleID: UUID
    var ownerID: UUID
    var category: String
    var imagesOnly = false
    @State private var pending: [PendingAttachment] = []
    @State private var loadingAttachments = false
    @State private var saving = false
    @State private var discardChanges = false
    var hasChanges: Bool { !pending.isEmpty || loadingAttachments }
    var body: some View {
        Form {
            Section { PendingAttachmentsPicker(pending: $pending, imagesOnly: imagesOnly, loading: $loadingAttachments) }
            Section { Text("Selected files are copied into your local vault.").font(.caption).foregroundStyle(.secondary) }
        }.disabled(saving).vaultEditorSafety(hasChanges: hasChanges, isBusy: saving, confirmDiscard: $discardChanges).vaultListAppearance().navigationTitle(imagesOnly ? "Add Photos" : "Add Attachments").navigationBarTitleDisplayMode(.inline).vaultErrorBanner()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if hasChanges { discardChanges = true } else { dismiss() } }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving…" : "Save") {
                    guard !saving, !loadingAttachments else { return }
                    saving = true
                    Task {
                        guard await store.addAttachments(pending, vehicleID: vehicleID, ownerID: ownerID, category: category) else { saving = false; return }
                        pending = []
                        dismiss()
                    }
                }.disabled(pending.isEmpty || loadingAttachments || saving) }
            }
    }
}

struct AttachmentThumbnail: View {
    @EnvironmentObject var store: VaultStore
    var item: VaultAttachment
    var body: some View {
        VaultMediaImage(url: store.fileURL(item), isPDF: item.isPDF, contentMode: item.isPDF ? .fit : .fill) {
            ZStack {
                Color.vaultCard
                RoundedRectangle(cornerRadius: 12).stroke(Color.vaultGold.opacity(0.18), lineWidth: 0.8).padding(18)
                VStack(spacing: 13) { Image(systemName: item.isPDF ? "doc.richtext" : "photo").font(.system(size: 30, weight: .ultraLight)); Text(item.isPDF ? "PDF DOCUMENT" : "IMAGE").font(.caption2.monospaced()).tracking(1.5) }.foregroundStyle(Color.vaultGold)
            }
        }
        .background(Color.vaultCard)
        .overlay(alignment: .bottomLeading) {
            if item.isPDF { Text("PDF").font(.caption2.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 5).background(.regularMaterial, in: Capsule()).padding(10) }
        }
        .accessibilityLabel(item.name)
    }
}

struct AttachmentsLibrary: View {
    @EnvironmentObject var store: VaultStore
    var vehicleID: UUID?
    @State private var vehicleFilter = "All"
    @State private var category = "All"
    @State private var fileType = "All"
    @State private var search = ""
    @State private var grid = true
    @State private var adding = false
    var hasFilters: Bool { vehicleFilter != "All" || category != "All" || fileType != "All" || !search.isEmpty }
    var files: [VaultAttachment] {
        store.database.attachments.filter {
            (vehicleID == nil || $0.vehicleID == vehicleID) && (vehicleFilter == "All" || $0.vehicleID.uuidString == vehicleFilter)
            && (category == "All" || $0.category == category) && (fileType == "All" || (fileType == "PDF" ? $0.isPDF : !$0.isPDF))
            && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
        }.sorted { $0.added > $1.added }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VaultPageHeading(eyebrow: "The file collection", title: "The tangible details.", subtitle: "A place for every document, image and receipt.")
                VaultCard {
                    VStack(spacing: 10) {
                        if vehicleID == nil { Picker("Vehicle", selection: $vehicleFilter) { Text("All Vehicles").tag("All"); ForEach(store.database.vehicles) { Text($0.title).tag($0.id.uuidString) } } }
                        Picker("Category", selection: $category) { ForEach(["All", "Documents", "Receipts", "Vehicle Photos", "Part Photos", "Other"], id: \.self) { Text($0) } }
                        Picker("File Type", selection: $fileType) { ForEach(["All", "Images", "PDF"], id: \.self) { Text($0) } }
                    }.pickerStyle(.menu)
                }
                if files.isEmpty {
                    if store.activeVehicles.isEmpty { VehicleRequired() }
                    else { EmptyVault(symbol: "tray", title: hasFilters ? "No matching attachments" : "No attachments yet",
                                      message: hasFilters ? "Clear your filters or try a different file name." : "Keep images and PDFs together, linked to a vehicle or record.",
                                      actionTitle: hasFilters ? "Clear Filters" : "Add Attachment", action: {
                        if hasFilters { vehicleFilter = "All"; category = "All"; fileType = "All"; search = "" }
                        else { adding = true }
                    }) }
                }
                if grid {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 14)], spacing: 20) {
                        ForEach(files) { item in
                            NavigationLink { AttachmentDetail(attachmentID: item.id) } label: {
                                VStack(alignment: .leading, spacing: 8) { AttachmentThumbnail(item: item).frame(height: 140).clipped().clipShape(RoundedRectangle(cornerRadius: 14)); Text(item.name).font(.subheadline.weight(.medium)).lineLimit(1); Text(item.category).font(.caption).foregroundStyle(.secondary) }.foregroundStyle(.primary)
                            }
                        }
                    }
                } else {
                    ForEach(files) { item in NavigationLink { AttachmentDetail(attachmentID: item.id) } label: { VaultCard { HStack { Image(systemName: item.isPDF ? "doc.richtext" : "photo").foregroundStyle(Color.vaultBlue); Text(item.name).font(.subheadline); Spacer(); Text(item.category).font(.caption).foregroundStyle(.secondary) }.foregroundStyle(.primary) } } }
                }
            }.padding(20).frame(maxWidth: 950).frame(maxWidth: .infinity)
        }.background(Color.vaultBackground).navigationTitle("Attachments").searchable(text: $search, prompt: "File name")
            .toolbar { ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { grid.toggle() } label: { Image(systemName: grid ? "list.bullet" : "square.grid.2x2") }.accessibilityLabel(grid ? "Show as list" : "Show as grid")
                Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add attachment").disabled(store.activeVehicles.isEmpty)
            } }
            .sheet(isPresented: $adding) { NavigationStack { LibraryAttachmentEditor(initialVehicleID: vehicleID ?? store.selectedVehicle?.id) } }
            .onChange(of: store.revision) { _ in
                if vehicleFilter != "All", !store.database.vehicles.contains(where: { $0.id.uuidString == vehicleFilter }) { vehicleFilter = "All" }
            }
    }
}

struct AttachmentDetail: View {
    @EnvironmentObject var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    var attachmentID: UUID
    @State private var renaming = false
    @State private var deleting = false
    @State private var fullScreen = false
    @State private var name = ""
    var item: VaultAttachment? { store.database.attachments.first { $0.id == attachmentID } }
    var body: some View {
        Group {
            if let item {
                List {
                    Section {
                        Button { fullScreen = true } label: {
                            ZStack(alignment: .bottomTrailing) {
                                AttachmentThumbnail(item: item).frame(height: 270).clipped().clipShape(RoundedRectangle(cornerRadius: 14))
                                Label("Open & Zoom", systemImage: "arrow.up.left.and.arrow.down.right").font(.caption.weight(.semibold)).padding(12).background(.regularMaterial, in: Capsule()).padding(12)
                            }
                        }.buttonStyle(.plain)
                    }.listRowInsets(EdgeInsets())
                    Section("File Details") {
                        InfoLine(title: "Name", value: item.name)
                        InfoLine(title: "Type", value: item.isPDF ? "PDF" : item.fileName.components(separatedBy: ".").last?.uppercased() ?? "Image")
                        InfoLine(title: "Size", value: VaultFormatting.fileSize(item.byteCount))
                        InfoLine(title: "Added", value: store.date(item.added))
                        InfoLine(title: "Category", value: item.category)
                        if let vehicle = store.vehicle(item.vehicleID) { NavigationLink("Vehicle: \(vehicle.title)") { VehicleDetail(vehicleID: vehicle.id) } }
                        if store.record(item.ownerID) != nil { NavigationLink("Open Related Record") { RecordDetail(recordID: item.ownerID) } }
                    }
                    Section("Actions") {
                        Button("Rename Attachment") { name = item.name; renaming = true }
                        if item.ownerID == item.vehicleID && !item.isPDF {
                            if store.vehicle(item.vehicleID)?.coverID == item.id { Label("Current Vehicle Cover", systemImage: "checkmark.circle.fill").foregroundStyle(Color.vaultGold) }
                            else { Button("Set as Vehicle Cover") { if var vehicle = store.vehicle(item.vehicleID) { vehicle.coverID = item.id; if store.saveVehicle(vehicle) { store.noticeMessage = "Vehicle cover updated." } } } }
                        }
                        Button("Delete Attachment", role: .destructive) { deleting = true }
                    }
                }
            } else { EmptyVault(symbol: "doc.questionmark", title: "Attachment unavailable", message: "This file may have been removed.") }
        }.vaultListAppearance().navigationTitle(item?.name ?? "Attachment").navigationBarTitleDisplayMode(.inline)
            .alert("Rename Attachment", isPresented: $renaming) {
                TextField("File name", text: $name)
                Button("Cancel", role: .cancel) { }
                Button("Save") { if let item { store.renameAttachment(item, name: name) } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .confirmationDialog("Permanently delete this attachment?", isPresented: $deleting, titleVisibility: .visible) { Button("Delete Attachment", role: .destructive) { if let item { if store.deleteAttachment(item) { dismiss() } } } }
            .fullScreenCover(isPresented: $fullScreen) { if let item { AttachmentViewer(item: item) } }
            .onChange(of: item?.id) { id in if id == nil { fullScreen = false; renaming = false } }
    }
}

struct AttachmentViewer: View {
    @EnvironmentObject var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    var item: VaultAttachment
    var body: some View {
        NavigationStack {
            Group {
                if item.isPDF { PDFReader(url: store.fileURL(item)) }
                else { VaultImageReader(url: store.fileURL(item)) }
            }.vaultListAppearance().navigationTitle(item.name).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct PDFReader: View {
    var url: URL
    @State private var document: VaultLoadedPDF?
    @State private var loading = true
    @State private var page = 1
    @State private var count = 0
    @State private var requestedPage = 1
    @State private var requestID = 0
    var body: some View {
        VStack(spacing: 0) {
            if let document {
                PDFCanvas(document: document.document, page: $page, count: $count, requestedPage: requestedPage, requestID: requestID)
            } else if loading {
                ProgressView("Opening PDF…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyVault(symbol: "doc.questionmark", title: "Unable to open this PDF", message: "The file may be missing or damaged. Restore a complete backup to recover it.").frame(maxHeight: .infinity)
            }
            if count > 0 {
                HStack {
                    Button { requestedPage = max(1, page - 1); requestID += 1 } label: { Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44) }.disabled(page <= 1).accessibilityLabel("Previous page")
                    Spacer(); Text("Page \(page) of \(count)").font(.subheadline.monospacedDigit()); Spacer()
                    Button { requestedPage = min(count, page + 1); requestID += 1 } label: { Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44) }.disabled(page >= count).accessibilityLabel("Next page")
                }.padding().background(.regularMaterial)
            }
        }
        .task(id: url) {
            loading = true
            document = nil; page = 1; count = 0; requestedPage = 1; requestID = 0
            let result = await VaultMediaRenderer.shared.openPDF(at: url)
            guard !Task.isCancelled else { return }
            document = result
            loading = false
        }
    }
}

struct PDFCanvas: UIViewRepresentable {
    var document: PDFDocument
    @Binding var page: Int
    @Binding var count: Int
    var requestedPage: Int
    var requestID: Int
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document; view.autoScales = true; view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical; view.backgroundColor = .secondarySystemBackground
        context.coordinator.observer = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak view, weak coordinator = context.coordinator] _ in
            Task { @MainActor in
                guard let view, let current = view.currentPage, let index = view.document?.index(for: current) else { return }
                coordinator?.parent.page = index + 1
            }
        }
        DispatchQueue.main.async { count = view.document?.pageCount ?? 0 }
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        if view.document !== document {
            view.document = document
            view.autoScales = true
            context.coordinator.lastRequest = -1
            DispatchQueue.main.async { count = document.pageCount; page = 1 }
        }
        if context.coordinator.lastRequest != requestID, let target = view.document?.page(at: requestedPage - 1) { view.go(to: target); context.coordinator.lastRequest = requestID }
    }
    class Coordinator {
        var parent: PDFCanvas
        var lastRequest = 0
        var observer: NSObjectProtocol?
        init(_ parent: PDFCanvas) { self.parent = parent }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}

struct ZoomImage: UIViewRepresentable {
    let image: UIImage
    func makeUIView(context: Context) -> ImageScrollView { ImageScrollView(image: image) }
    func updateUIView(_ uiView: ImageScrollView, context: Context) { uiView.updateImage(image) }
}

final class ImageScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView: UIImageView
    private var viewport = CGSize.zero
    init(image: UIImage) {
        imageView = UIImageView(image: image)
        super.init(frame: .zero)
        minimumZoomScale = 1; maximumZoomScale = 5; delegate = self
        bouncesZoom = true
        showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        let tap = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        tap.numberOfTapsRequired = 2; addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func updateImage(_ image: UIImage) {
        guard imageView.image !== image else { return }
        imageView.image = image
        viewport = .zero
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != viewport, bounds.width > 0, bounds.height > 0, let image = imageView.image {
            viewport = bounds.size
            setZoomScale(1, animated: false)
            let scale = min(bounds.width / max(1, image.size.width), bounds.height / max(1, image.size.height))
            let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            imageView.frame = CGRect(origin: .zero, size: fitted)
            contentSize = fitted
        }
        centerImage()
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }
    private func centerImage() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != inset { contentInset = inset }
    }
    @objc private func doubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1.01 { setZoomScale(1, animated: true); return }
        let point = gesture.location(in: imageView)
        let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
    }
}

struct LibraryAttachmentEditor: View {
    @EnvironmentObject var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    var initialVehicleID: UUID?
    @State private var vehicleID: UUID?
    @State private var ownerID = ""
    @State private var category = "Other"
    @State private var pending: [PendingAttachment] = []
    @State private var loadingAttachments = false
    @State private var saving = false
    @State private var discardChanges = false
    @State private var initialized = false
    @State private var initialSelection: UUID?
    var hasChanges: Bool { !pending.isEmpty || loadingAttachments || !ownerID.isEmpty || category != "Other" || vehicleID != initialSelection }
    var body: some View {
        Form {
            Section("Related Vehicle") {
                Picker("Vehicle", selection: $vehicleID) {
                    Text("Select Vehicle").tag(Optional<UUID>.none)
                    ForEach(store.activeVehicles) { Text($0.title).tag(Optional($0.id)) }
                }.onChange(of: vehicleID) { _ in ownerID = "" }
                if let vehicleID {
                    Picker("Related Record", selection: $ownerID) {
                        Text("Vehicle Only").tag("")
                        ForEach(store.database.records.filter { $0.vehicleID == vehicleID && !$0.archived }) { Text("\($0.kind.title): \($0.title)").tag($0.id.uuidString) }
                    }
                }
                Picker("Category", selection: $category) { ForEach(["Documents", "Receipts", "Vehicle Photos", "Part Photos", "Other"], id: \.self) { Text($0) } }
            }
            Section("Files") { PendingAttachmentsPicker(pending: $pending, loading: $loadingAttachments) }
        }.disabled(saving).vaultEditorSafety(hasChanges: hasChanges, isBusy: saving, confirmDiscard: $discardChanges).vaultListAppearance().navigationTitle("Add Attachments").navigationBarTitleDisplayMode(.inline).vaultErrorBanner()
            .onAppear {
                if !initialized {
                    initialized = true
                    vehicleID = store.activeVehicles.first(where: { $0.id == initialVehicleID })?.id ?? store.selectedVehicle?.id
                    initialSelection = vehicleID
                }
            }
            .onChange(of: store.revision) { _ in
                if let id = vehicleID, !store.activeVehicles.contains(where: { $0.id == id }) { vehicleID = store.selectedVehicle?.id; ownerID = "" }
                if let id = UUID(uuidString: ownerID), store.record(id)?.vehicleID != vehicleID { ownerID = "" }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if hasChanges { discardChanges = true } else { dismiss() } }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving…" : "Save") {
                    guard let vehicleID, !saving, !loadingAttachments else { return }
                    saving = true
                    Task {
                        if await store.addAttachments(pending, vehicleID: vehicleID, ownerID: UUID(uuidString: ownerID) ?? vehicleID, category: category) { dismiss() }
                        else { saving = false }
                    }
                }.disabled(vehicleID == nil || pending.isEmpty || loadingAttachments || saving) }
            }
    }
}
