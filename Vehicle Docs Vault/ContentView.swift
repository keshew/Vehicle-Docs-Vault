import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var store: VaultStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var launching = true
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    @ObservedObject private var notificationInbox = VaultNotificationInbox.shared
    var body: some View {
        Group {
            if launching { launch }
            else if store.loadIssue != nil { VaultRecoveryView() }
            else if !store.preferences.onboarded { OnboardingView() }
            else { MainTabs().id(store.generation) }
        }
        .tint(.vaultGold)
        .preferredColorScheme(store.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))
        .disabled(store.isTransferring)
        .overlay { if store.isTransferring { ProgressView("Working with your vault…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20)) } }
        .vaultErrorBanner()
        .task { await Task.yield(); launching = false; await store.scheduleNotifications() }
        .onChange(of: scenePhase) { phase in if phase == .active { store.refreshClock(); Task { await store.scheduleNotifications() }; openPendingNotification() } }
        .onReceive(clock) { _ in if scenePhase == .active { store.refreshClock() } }
        .onChange(of: notificationInbox.recordID) { _ in openPendingNotification() }
        .onChange(of: launching) { _ in openPendingNotification() }
    }
    private func openPendingNotification() {
        guard !launching, store.loadIssue == nil, let id = notificationInbox.recordID else { return }
        Task { @MainActor in
            for _ in 0..<8 {
                guard notificationInbox.recordID == id else { return }
                if VaultNotificationPresenter.present(recordID: id, store: store) { notificationInbox.recordID = nil; return }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }
    var launch: some View {
        ZStack {
            Color.vaultNavy.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "square.stack.3d.up").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(Color.vaultChampagne).frame(width: 90, height: 90).overlay(RoundedRectangle(cornerRadius: 23).stroke(Color.vaultChampagne.opacity(0.25), lineWidth: 0.7))
                Text("Vehicle Docs Vault").font(.vaultDisplay(29)).foregroundStyle(.white)
                Text("THE PERSONAL VEHICLE ARCHIVE").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(2).foregroundStyle(Color.vaultChampagne)
                ProgressView().tint(.white).padding(.top, 10)
            }
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView() }.tabItem { Label("Home", systemImage: "house") }
            NavigationStack { RecordsList(kind: .document) }.tabItem { Label("Documents", systemImage: "doc.text") }
            NavigationStack { PartsHub() }.tabItem { Label("Parts", systemImage: "gearshape.2") }
            NavigationStack { TimelineView() }.tabItem { Label("Timeline", systemImage: "clock.arrow.circlepath") }
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject var store: VaultStore
    @State private var page = 0
    let titles = ["Everything about your vehicle, organized.", "Keep important documents together", "Store essential vehicle details", "Remember what was replaced", "Manage more than one vehicle"]
    let subtitles = ["A private home for your documents, parts, tires and important dates. Everything stays on your device.", "Registration, insurance, inspections and ownership records. With images and PDFs, ready when you need them.", "Keep your VIN, license plate, engine and technical specifications within reach.", "Keep a clear history of tires, batteries, filters, brakes and fluids. Your own records, without mechanical advice.", "Give each vehicle its own space for documents, notes, reminders and history. No account needed."]
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 18, weight: .light)).foregroundStyle(Color.vaultGold)
                    Text("VEHICLE DOCS VAULT").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.8)
                    Spacer()
                    Text("0\(page + 1) / 05").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }.padding(26)
                TabView(selection: $page) {
                    ForEach(0..<5) { index in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 26) {
                                OnboardingArtwork(page: index).frame(height: min(geometry.size.height * 0.40, 330))
                                Text(titles[index]).font(.vaultDisplay(35)).tracking(-1.1).foregroundStyle(Color.vaultInk)
                                Text(subtitles[index]).font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(5)
                            }.padding(.horizontal, 26).padding(.top, 18).frame(maxWidth: 570)
                        }.tag(index)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
                VStack(spacing: 22) {
                    HStack(spacing: 7) { ForEach(0..<5) { index in Capsule().fill(index == page ? Color.vaultGold : Color.secondary.opacity(0.15)).frame(width: index == page ? 25 : 7, height: 6) } }
                    Button {
                        if page < 4 { withAnimation { page += 1 } }
                        else { store.updatePreferences { $0.onboarded = true } }
                    } label: { HStack { Spacer(); Text(page == 4 ? "Get Started" : "Continue"); Spacer(); Image(systemName: "arrow.right") } }.buttonStyle(VaultPrimaryButton())
                    if page > 0 { Button("Back") { withAnimation { page -= 1 } }.font(.subheadline).foregroundStyle(.secondary) }
                }.padding(26).frame(maxWidth: 570)
            }.frame(maxWidth: .infinity).background(Color.vaultBackground)
        }
    }
}
