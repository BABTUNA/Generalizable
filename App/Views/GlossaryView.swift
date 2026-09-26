import SwiftUI

/// Medical words from the report with plain meanings.
struct GlossaryView: View {
  var terms: [GlossaryTerm]
  @State private var isExpanded = false

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(terms) { term in
          VStack(alignment: .leading, spacing: 2) {
            Text(term.term)
              .font(.subheadline.weight(.semibold))
            Text(term.meaning)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding(.top, 8)
    } label: {
      Label("Words in this report", systemImage: "character.book.closed")
        .font(.headline)
    }
    .padding()
    .background(.background, in: .rect(cornerRadius: 16))
  }
}
