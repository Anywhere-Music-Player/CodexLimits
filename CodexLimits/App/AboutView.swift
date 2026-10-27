import AppKit
import SwiftUI

struct AboutInformation {
    static let repositoryURL = URL(string: "https://github.com/Anywhere-Music-Player/CodexLimits")!
    static let releasesURL = repositoryURL.appendingPathComponent("releases")
    static let issuesURL = repositoryURL.appendingPathComponent("issues/new/choose")
    static let licenseURL = repositoryURL.appendingPathComponent("blob/main/LICENSE")

    let version: String
    let build: String
    let identifier: String
    let systemVersion: String
    let architecture: String
    let copyright: String

    init(bundle: Bundle = .main) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        identifier = bundle.bundleIdentifier ?? "—"
        copyright = bundle.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "© 2026 Volodymyr"
        systemVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #if arch(arm64)
        architecture = "Apple silicon (arm64)"
        #elseif arch(x86_64)
        architecture = "Intel (x86_64)"
        #else
        architecture = "—"
        #endif
    }

    // Keep diagnostics limited to app/system metadata, with no account or device identifiers.
    var supportSummary: String {
        """
        CodexLimits
        \(String(localized: "Version")): \(version)
        \(String(localized: "Build")): \(build)
        macOS: \(systemVersion)
        \(String(localized: "Architecture")): \(architecture)
        \(String(localized: "App identifier")): \(identifier)
        """
    }
}

struct AboutView: View {
    let information: AboutInformation

    init(information: AboutInformation = AboutInformation()) {
        self.information = information
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "CodexLimits")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Your remaining ChatGPT Codex usage, at a glance.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 12) {
                LabeledContent("Version") { Text(verbatim: information.version) }
                LabeledContent("Build") { Text(verbatim: information.build) }
                LabeledContent("Developer") { Text(verbatim: "Volodymyr Klymenko") }
                LabeledContent("License") {
                    Link(destination: AboutInformation.licenseURL) { Text(verbatim: "MIT") }
                }
            }
            .textSelection(.enabled)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Link(destination: AboutInformation.repositoryURL) {
                    Label("Source code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: AboutInformation.releasesURL) {
                    Label("Release notes", systemImage: "doc.text")
                }
                Link(destination: AboutInformation.issuesURL) {
                    Label("Report an issue", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                }
            }

            DisclosureGroup("System information") {
                VStack(spacing: 12) {
                    LabeledContent { Text(verbatim: information.systemVersion) } label: { Text(verbatim: "macOS") }
                    LabeledContent("Architecture") { Text(verbatim: information.architecture) }
                    LabeledContent("App identifier") { Text(verbatim: information.identifier) }
                }
                .font(.callout)
                .textSelection(.enabled)
                .padding(.top, 10)
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(information.supportSummary, forType: .string)
            } label: {
                Label("Copy app information", systemImage: "doc.on.doc")
            }

            Text(verbatim: information.copyright)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 620, alignment: .leading)
    }
}
