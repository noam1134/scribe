import ScribeCore
import SwiftUI

/// Settings › Claude: the connector link that lets Claude add items and see
/// what's coming up (`mailbox/README.md`). The link is shared with the
/// user's other devices through iCloud Keychain.
struct ClaudeSettingsSection: View {
    @State private var link = ""
    @State private var linkRejected = false

    var body: some View {
        let mailbox = MailboxSync.shared
        Section {
            if let connection = mailbox.connection {
                LabeledContent("Mailbox", value: connection.host)
                    .accessibilityIdentifier("claudeMailboxHost")
                // Keeps "just now" and "at 09:14" honest while Settings stays open.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let text = MailboxStatusText(status: mailbox.status, isSyncing: mailbox.isSyncing, now: context.date)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text.line)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("claudeStatus")
                        if let problem = text.problem {
                            Text(problem)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("claudeProblem")
                        }
                    }
                }
                Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await mailbox.syncNow() }
                }
                .disabled(mailbox.isSyncing)
                .accessibilityIdentifier("claudeSyncNow")
                Button("Disconnect", systemImage: "xmark.circle", role: .destructive) {
                    link = ""
                    mailbox.disconnect()
                }
                .foregroundStyle(.red)
                .accessibilityIdentifier("claudeDisconnect")
            } else {
                linkField
                if linkRejected {
                    Text(MailboxStatusText.linkProblem)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("claudeLinkProblem")
                }
                Button("Connect", systemImage: "link", action: connect)
                    .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("claudeConnect")
            }
        } header: {
            Text("Claude")
        } footer: {
            Text(MailboxStatusText.footer)
        }
    }

    private var linkField: some View {
        TextField("Connector Link", text: $link, prompt: Text("https://…/mcp"))
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .textContentType(.URL)
            #endif
            .onSubmit(connect)
            .onChange(of: link) { linkRejected = false }
            .accessibilityIdentifier("claudeLinkField")
    }

    private func connect() {
        if MailboxSync.shared.connect(link: link) {
            link = ""
        } else {
            linkRejected = true
        }
    }
}
