import SwiftUI

struct VaultRecoveryView: View {
    @EnvironmentObject var store: VaultStore
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VaultPageHeading(eyebrow: "Data recovery", title: "Your files are preserved.", subtitle: "The vault could not be opened safely. Restore a saved copy or import a complete export to continue.")
                    VaultCard { Text(store.loadIssue ?? "").font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }
                    NavigationLink { BackupView() } label: { Label("Review Local Backups", systemImage: "externaldrive").frame(maxWidth: .infinity) }.buttonStyle(VaultPrimaryButton())
                    NavigationLink { ImportDataView() } label: { Label("Import a Saved Export", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity) }.buttonStyle(VaultPrimaryButton())
                    NavigationLink { ResetDataView() } label: { Label("Reset App Data", systemImage: "trash").foregroundStyle(.red) }.padding(.top, 10)
                }.padding(24).frame(maxWidth: 700).frame(maxWidth: .infinity)
            }.background(Color.vaultBackground).navigationTitle("Recover Vault").navigationBarTitleDisplayMode(.inline)
        }
    }
}
