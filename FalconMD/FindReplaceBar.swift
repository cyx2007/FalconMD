import SwiftUI

/// Compact find / replace strip, pinned above the editor like TextEdit's find bar.
struct FindReplaceBar: View {
    @Bindable var session: EditorSession
    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Find")
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)

                TextField("Search", text: $session.findQuery)
                    .textFieldStyle(.roundedBorder)
                    .focused($queryFocused)
                    .onSubmit { session.findNext() }
                    .onChange(of: session.findQuery) { _, _ in
                        session.runFind(resetIndex: true)
                    }

                Text(matchLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 72, alignment: .leading)
                    .accessibilityLabel(matchLabel)

                ControlGroup {
                    Button {
                        session.findPrevious()
                    } label: {
                        Label("Previous", systemImage: "chevron.up")
                    }
                    .disabled(session.findCount == 0)
                    .help("Find Previous")

                    Button {
                        session.findNext()
                    } label: {
                        Label("Next", systemImage: "chevron.down")
                    }
                    .disabled(session.findCount == 0)
                    .help("Find Next")
                }
                .controlSize(.small)
                .labelsHidden()

                Toggle("Replace", isOn: $session.showsReplace)
                    .toggleStyle(.button)
                    .controlSize(.small)

                Button("Done") { session.dismissFind() }
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if session.showsReplace {
                HStack(spacing: 8) {
                    Text("Replace")
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)

                    TextField("Replace with", text: $session.findReplacement)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { session.replaceCurrentMatch() }

                    Button("Replace") { session.replaceCurrentMatch() }
                        .controlSize(.small)
                        .disabled(session.findCount == 0)

                    Button("All") { session.replaceAllMatches() }
                        .controlSize(.small)
                        .disabled(session.findQuery.isEmpty)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }

            Divider()
        }
        .background(.bar)
        .onAppear { queryFocused = true }
        .onChange(of: session.findFocusNonce) { _, _ in
            queryFocused = true
        }
        .onExitCommand { session.dismissFind() }
    }

    private var matchLabel: String {
        if session.findQuery.isEmpty { return "" }
        if session.findCount == 0 { return "No results" }
        return "\(session.findIndex + 1) of \(session.findCount)"
    }
}
