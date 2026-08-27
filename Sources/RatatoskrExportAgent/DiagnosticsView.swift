import SwiftUI

struct DiagnosticsView: View {
  @ObservedObject var viewModel: DiagnosticsViewModel
  let exportReport: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      List(viewModel.rows) { row in
        HStack(alignment: .firstTextBaseline) {
          Text(row.title)
          Spacer()
          Text(row.value)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
        }
      }
      Divider()
      HStack {
        Text("No paths, filenames, contents, credentials, or endpoint URLs are shown.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Export Support Report…", action: exportReport)
      }
      .padding(10)
    }
    .frame(minWidth: 620, minHeight: 320)
  }
}
