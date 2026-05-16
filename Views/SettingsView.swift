import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var onLogout: () -> Void

    @State private var offsets: [Int] = NotificationService.loadNotificationOffsets()
    @State private var notifyNewAssignment: Bool = NotificationService.loadNewAssignmentNotification()
    @State private var showAddOffset = false
    @State private var showLogoutConfirm = false
    @State private var totpSecret = ""
    @State private var hasTotpSecret = CredentialStore.loadTotpSecret() != nil
    @State private var showTotpInvalidAlert = false
    @State private var showQRScanner = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    private let githubURL = URL(string: "https://github.com/Radian0523/kulms-ios-webview")!

    private let presetOffsets = [10, 30, 60, 180, 300, 720, 1440, 2880, 4320]

    private var sortedOffsets: [Int] { offsets.sorted(by: >) }

    private var availablePresets: [Int] {
        presetOffsets.filter { !offsets.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Notifications
                Section(String(localized: "sectionNotifications")) {
                    Toggle(String(localized: "notifyNewAssignment"), isOn: $notifyNewAssignment)
                        .onChange(of: notifyNewAssignment) { _, newValue in
                            NotificationService.saveNewAssignmentNotification(newValue)
                        }

                    ForEach(sortedOffsets, id: \.self) { offset in
                        Text(NotificationService.formatOffsetLabelBefore(offset))
                    }
                    .onDelete { indexSet in
                        let toRemove = indexSet.map { sortedOffsets[$0] }
                        offsets.removeAll { toRemove.contains($0) }
                        NotificationService.saveNotificationOffsets(offsets)
                    }

                    if !availablePresets.isEmpty {
                        Button {
                            showAddOffset = true
                        } label: {
                            Label(String(localized: "addTiming"), systemImage: "plus")
                        }
                    }

                }

                // MARK: - TOTP
                Section(String(localized: "totpSectionTitle")) {
                    if hasTotpSecret {
                        HStack {
                            Label(String(localized: "totpConfigured"), systemImage: "checkmark.shield.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            Button(String(localized: "totpDelete"), role: .destructive) {
                                CredentialStore.clearTotpSecret()
                                hasTotpSecret = false
                                totpSecret = ""
                            }
                            .font(.subheadline)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "totpDescription"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack {
                                TextField(String(localized: "totpPlaceholder"), text: $totpSecret)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                    .font(.system(.body, design: .monospaced))
                                Button(String(localized: "totpSave")) {
                                    let cleaned = totpSecret
                                        .replacingOccurrences(of: " ", with: "")
                                        .replacingOccurrences(of: "-", with: "")
                                    if TOTPGenerator.isValidBase32(cleaned) {
                                        CredentialStore.saveTotpSecret(cleaned)
                                        hasTotpSecret = true
                                        totpSecret = ""
                                    } else {
                                        showTotpInvalidAlert = true
                                    }
                                }
                                .disabled(totpSecret.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                            Button {
                                showQRScanner = true
                            } label: {
                                Label(String(localized: "totpScanQr"), systemImage: "qrcode.viewfinder")
                                    .font(.subheadline)
                            }
                        }
                    }
                }

                // MARK: - Security
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "securitySectionTitle"))
                            .font(.headline)
                        Text(String(localized: "securityDescription"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - App Info
                Section(String(localized: "appInfoSection")) {
                    LabeledContent(String(localized: "version"), value: appVersion)

                    Link(destination: githubURL) {
                        HStack {
                            Text(String(localized: "sourceCode"))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("GitHub")
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // MARK: - Logout
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Text(String(localized: "logout"))
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "settingsTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "close")) {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                String(localized: "addTiming"),
                isPresented: $showAddOffset,
                titleVisibility: .visible
            ) {
                ForEach(availablePresets, id: \.self) { offset in
                    Button(NotificationService.formatOffsetLabelBefore(offset)) {
                        offsets.append(offset)
                        NotificationService.saveNotificationOffsets(offsets)
                    }
                }
            }
            .alert(String(localized: "totpInvalidTitle"), isPresented: $showTotpInvalidAlert) {
                Button(String(localized: "close"), role: .cancel) {}
            } message: {
                Text(String(localized: "totpInvalidMessage"))
            }
            .sheet(isPresented: $showQRScanner) {
                QRCodeScannerView { secret in
                    CredentialStore.saveTotpSecret(secret)
                    hasTotpSecret = true
                    totpSecret = ""
                }
            }
            .alert(String(localized: "logoutConfirm"), isPresented: $showLogoutConfirm) {
                Button(String(localized: "logout"), role: .destructive) {
                    onLogout()
                }
                Button(String(localized: "cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "logoutConfirmBody"))
            }
        }
    }
}
