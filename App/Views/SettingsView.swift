import SwiftUI

/// Claude key and model settings. The key is kept in the Keychain, never in UserDefaults.
struct SettingsView: View {
  @Environment(CaseLibrary.self) private var library
  @Environment(\.dismiss) private var dismiss
  @State private var keyDraft = ""

  var body: some View {
    @Bindable var library = library
    NavigationStack {
      Form {
        Section {
          SecureField("Anthropic API key", text: $keyDraft)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          Button("Save Key") {
            APIKeyStore.shared.write(keyDraft)
            keyDraft = ""
            library.refreshKeyState()
          }
          .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
          if library.hasAPIKey {
            Button("Remove Key", role: .destructive) {
              APIKeyStore.shared.delete()
              library.refreshKeyState()
            }
          }
        } header: {
          Text("Claude")
        } footer: {
          Text(library.hasAPIKey ? "A key is saved on this device." : "Without a key, reports are read on this device with a simpler reader.")
        }

        Section("Model") {
          Picker("Model", selection: $library.model) {
            ForEach(ClaudeModel.allCases) { model in
              Text(model.displayName).tag(model)
            }
          }
          .pickerStyle(.inline)
          .labelsHidden()
        }

        Section("About") {
          Text("Generalizable explains medical imaging in plain words. It doesn't diagnose or replace your doctor. The sample patient and the body model are synthetic.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}
