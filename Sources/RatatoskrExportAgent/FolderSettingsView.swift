import AgentCore
import SwiftUI

/// The folder-settings surface: one row per watched folder with its
/// controls, plus add and remove flows.
struct FolderSettingsView: View {
  @ObservedObject var viewModel: FolderSettingsViewModel
  @State private var pendingRemoval: FolderRow.ID?
  @State private var showingRemovalConfirmation = false

  var body: some View {
    VStack(spacing: 0) {
      content
      Divider()
      footer
    }
    .frame(minWidth: 520, minHeight: 300)
    .alert(
      "Remove watched folder?",
      isPresented: $showingRemovalConfirmation
    ) {
      Button("Cancel", role: .cancel) {}
      Button("Remove", role: .destructive) {
        if let id = pendingRemoval {
          viewModel.removeConfirmed(id: id)
        }
      }
    } message: {
      Text(
        "The folder will stop being watched. Archives already imported are not affected."
      )
    }
  }

  @ViewBuilder
  private var content: some View {
    if viewModel.rows.isEmpty {
      Text("No folders are being watched yet.")
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      List(viewModel.rows) { row in
        FolderRowView(row: row, viewModel: viewModel, requestRemove: requestRemove)
      }
    }
  }

  private var footer: some View {
    HStack {
      if let failure = viewModel.changeFailure {
        Text(failure)
          .font(.caption)
          .foregroundStyle(.red)
      }
      Spacer()
      Button("Add Folder…") {
        viewModel.addFolderFromPicker()
      }
    }
    .padding(8)
  }

  private func requestRemove(_ id: FolderRow.ID) {
    pendingRemoval = id
    showingRemovalConfirmation = true
  }
}

private struct FolderRowView: View {
  let row: FolderRow
  @ObservedObject var viewModel: FolderSettingsViewModel
  let requestRemove: (FolderRow.ID) -> Void

  var body: some View {
    HStack(spacing: 12) {
      Toggle("", isOn: enabledBinding).labelsHidden()
      VStack(alignment: .leading, spacing: 2) {
        Text(row.displayPath)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(row.displayPath)
        Text(accessDescription)
          .font(.caption)
          .foregroundStyle(accessColor)
      }
      Spacer()
      Picker("Archive", selection: policyBinding) {
        Text("Archive after upload").tag(FolderArchivePolicy.archiveAfterUpload)
        Text("Preserve in place").tag(FolderArchivePolicy.preserveInPlace)
      }
      .labelsHidden()
      Button("Remove…") {
        requestRemove(row.id)
      }
    }
    .opacity(row.isEnabled ? 1 : 0.5)
  }

  private var enabledBinding: Binding<Bool> {
    Binding(
      get: { row.isEnabled },
      set: { viewModel.setEnabled($0, id: row.id) }
    )
  }

  private var policyBinding: Binding<FolderArchivePolicy> {
    Binding(
      get: { row.archivePolicy },
      set: { viewModel.setArchivePolicy($0, id: row.id) }
    )
  }

  private var accessDescription: String {
    switch row.accessState {
    case .accessible:
      "Accessible"
    case .needsReauthorization:
      "Needs re-authorization - pick the folder again"
    case .missing:
      "Folder is missing"
    case .denied:
      "Access denied"
    }
  }

  private var accessColor: Color {
    switch row.accessState {
    case .accessible:
      .green
    case .needsReauthorization, .missing:
      .orange
    case .denied:
      .red
    }
  }
}
