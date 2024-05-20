//
//  ChatInfoView.swift
//  SimpleX
//
//  Created by Evgeny Poberezkin on 05/02/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI
import SimpleXChat

func infoRow(_ title: LocalizedStringKey, _ value: String) -> some View {
    HStack {
        Text(title)
        Spacer()
        Text(value)
            .foregroundStyle(.secondary)
    }
}

func infoRow(_ title: Text, _ value: String) -> some View {
    HStack {
        title
        Spacer()
        Text(value)
            .foregroundStyle(.secondary)
    }
}

func localizedInfoRow(_ title: LocalizedStringKey, _ value: LocalizedStringKey) -> some View {
    HStack {
        Text(title)
        Spacer()
        Text(value)
            .foregroundStyle(.secondary)
    }
}

@ViewBuilder func smpServers(_ title: LocalizedStringKey, _ servers: [String]) -> some View {
    if servers.count > 0 {
        HStack {
            Text(title).frame(width: 120, alignment: .leading)
            Button(serverHost(servers[0])) {
                UIPasteboard.general.string = servers.joined(separator: ";")
            }
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
    }
}

func serverHost(_ s: String) -> String {
    if let i = s.range(of: "@")?.lowerBound {
        return String(s[i...].dropFirst())
    } else {
        return s
    }
}

enum SendReceipts: Identifiable, Hashable {
    case yes
    case no
    case userDefault(Bool)

    var id: Self { self }

    var text: LocalizedStringKey {
        switch self {
        case .yes: return "yes"
        case .no: return "no"
        case let .userDefault(on): return on ? "default (yes)" : "default (no)"
        }
    }

    func bool() -> Bool? {
        switch self {
        case .yes: return true
        case .no: return false
        case .userDefault: return nil
        }
    }

    static func fromBool(_ enable: Bool?, userDefault def: Bool) -> SendReceipts {
        if let enable = enable {
            return enable ? .yes : .no
        }
        return .userDefault(def)
    }
}

enum ContactDeleteMode {
    case full
    case entity

    public func toChatDeleteMode(notify: Bool) -> ChatDeleteMode {
        switch self {
        case .full: .full(notify: notify)
        case .entity: .entity(notify: notify)
        }
    }
}

struct ChatInfoView: View {
    @EnvironmentObject var chatModel: ChatModel
    @Environment(\.dismiss) var dismiss: DismissAction
    var openedFromChatView: Bool
    @ObservedObject var chat: Chat
    @State var contact: Contact
    @State var localAlias: String
    @State private var connectionStats: ConnectionStats? = nil
    @State private var customUserProfile: Profile? = nil
    @State private var connectionCode: String? = nil
    @FocusState private var aliasTextFieldFocused: Bool
    @State private var alert: ChatInfoViewAlert? = nil
    @State private var actionSheet: ChatInfoViewActionSheet? = nil
    @State private var showConnectContactViaAddressDialog = false
    @State private var sendReceipts = SendReceipts.userDefault(true)
    @State private var sendReceiptsUserDefault = true
    @AppStorage(DEFAULT_DEVELOPER_TOOLS) private var developerTools = false
    @AppStorage(DEFAULT_SHOW_DELETE_CONTACT_NOTICE) private var showDeleteContactNotice = true

    enum ChatInfoViewAlert: Identifiable {
        case clearChatAlert
        case networkStatusAlert
        case switchAddressAlert
        case abortSwitchAddressAlert
        case syncConnectionForceAlert
        case deleteContactNotice
        case error(title: LocalizedStringKey, error: LocalizedStringKey = "")

        var id: String {
            switch self {
            case .clearChatAlert: return "clearChatAlert"
            case .networkStatusAlert: return "networkStatusAlert"
            case .switchAddressAlert: return "switchAddressAlert"
            case .abortSwitchAddressAlert: return "abortSwitchAddressAlert"
            case .syncConnectionForceAlert: return "syncConnectionForceAlert"
            case .deleteContactNotice: return "deleteContactNotice"
            case let .error(title, _): return "error \(title)"
            }
        }
    }

    enum ChatInfoViewActionSheet: Identifiable {
        case deleteContactActionSheet
        case confirmDeleteContactActionSheet(contactDeleteMode: ContactDeleteMode)

        var id: String {
            switch self {
            case .deleteContactActionSheet: return "deleteContactActionSheet"
            case .confirmDeleteContactActionSheet: return "confirmDeleteContactActionSheet"
            }
        }
    }

    var body: some View {
        NavigationView {
            List {
                contactInfoHeader()
                    .listRowBackground(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        aliasTextFieldFocused = false
                    }

                Group {
                    localAliasTextEdit()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                HStack {
                    if contact.activeConn == nil && contact.profile.contactLink != nil && contact.active {
                        connectButton()
                    } else if !contact.active && !contact.chatDeleted {
                        openButton()
                    } else {
                        messageButton()
                    }
                    Spacer()
                    callButton()
                    Spacer()
                    videoButton()
                }
                .padding(.horizontal)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if let customUserProfile = customUserProfile {
                    Section("Incognito") {
                        HStack {
                            Text("Your random profile")
                            Spacer()
                            Text(customUserProfile.chatViewName)
                                .foregroundStyle(.indigo)
                        }
                    }
                }

                Section {
                    if let code = connectionCode { verifyCodeButton(code) }
                    contactPreferencesButton()
                    sendReceiptsOption()
                    if let connStats = connectionStats,
                       connStats.ratchetSyncAllowed {
                        synchronizeConnectionButton()
                    }
                    //                    } else if developerTools {
                    //                        synchronizeConnectionButtonForce()
                    //                    }
                }
                .disabled(!contact.ready || !contact.active)

                if let conn = contact.activeConn {
                    Section {
                        infoRow(Text(String("E2E encryption")), conn.connPQEnabled ? "Quantum resistant" : "Standard")
                    }
                }

                if let contactLink = contact.contactLink {
                    Section {
                        SimpleXLinkQRCode(uri: contactLink)
                        Button {
                            showShareSheet(items: [simplexChatLink(contactLink)])
                        } label: {
                            Label("Share address", systemImage: "square.and.arrow.up")
                        }
                    } header: {
                        Text("Address")
                    } footer: {
                        Text("You can share this address with your contacts to let them connect with **\(contact.displayName)**.")
                    }
                }

                if contact.ready && contact.active {
                    Section("Servers") {
                        networkStatusRow()
                            .onTapGesture {
                                alert = .networkStatusAlert
                            }
                        if let connStats = connectionStats {
                            Button("Change receiving address") {
                                alert = .switchAddressAlert
                            }
                            .disabled(
                                connStats.rcvQueuesInfo.contains { $0.rcvSwitchStatus != nil }
                                || connStats.ratchetSyncSendProhibited
                            )
                            if connStats.rcvQueuesInfo.contains(where: { $0.rcvSwitchStatus != nil }) {
                                Button("Abort changing address") {
                                    alert = .abortSwitchAddressAlert
                                }
                                .disabled(
                                    connStats.rcvQueuesInfo.contains { $0.rcvSwitchStatus != nil && !$0.canAbortSwitch }
                                    || connStats.ratchetSyncSendProhibited
                                )
                            }
                            smpServers("Receiving via", connStats.rcvQueuesInfo.map { $0.rcvServer })
                            smpServers("Sending via", connStats.sndQueuesInfo.map { $0.sndServer })
                        }
                    }
                }

                Section {
                    clearChatButton()
                    deleteContactButton()
                }

                if developerTools {
                    Section(header: Text("For console")) {
                        infoRow("Local name", chat.chatInfo.localDisplayName)
                        infoRow("Database ID", "\(chat.chatInfo.apiId)")
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if let currentUser = chatModel.currentUser {
                sendReceiptsUserDefault = currentUser.sendRcptsContacts
            }
            sendReceipts = SendReceipts.fromBool(contact.chatSettings.sendRcpts, userDefault: sendReceiptsUserDefault)

            Task {
                do {
                    let (stats, profile) = try await apiContactInfo(chat.chatInfo.apiId)
                    let (ct, code) = try await apiGetContactCode(chat.chatInfo.apiId)
                    await MainActor.run {
                        connectionStats = stats
                        customUserProfile = profile
                        connectionCode = code
                        if contact.activeConn?.connectionCode != ct.activeConn?.connectionCode {
                            chat.chatInfo = .direct(contact: ct)
                        }
                    }
                } catch let error {
                    logger.error("apiContactInfo or apiGetContactCode error: \(responseError(error))")
                }
            }
        }
        .alert(item: $alert) { alertItem in
            switch(alertItem) {
            case .clearChatAlert: return clearChatAlert()
            case .networkStatusAlert: return networkStatusAlert()
            case .switchAddressAlert: return switchAddressAlert(switchContactAddress)
            case .abortSwitchAddressAlert: return abortSwitchAddressAlert(abortSwitchContactAddress)
            case .syncConnectionForceAlert: return syncConnectionForceAlert({ syncContactConnection(force: true) })
            case .deleteContactNotice: return deleteContactNotice(contact)
            case let .error(title, error): return mkAlert(title: title, message: error)
            }
        }
        .actionSheet(item: $actionSheet) { sheet in
            switch(sheet) {
            case .deleteContactActionSheet:
                var sheetButtons: [ActionSheet.Button] = []
                sheetButtons.append(
                    .destructive(Text("Delete contact")) { actionSheet = .confirmDeleteContactActionSheet(contactDeleteMode: .full) }
                )
                if !contact.chatDeleted {
                    sheetButtons.append(
                        .destructive(Text("Delete contact, keep conversation")) { actionSheet = .confirmDeleteContactActionSheet(contactDeleteMode: .entity) }
                    )
                }
                sheetButtons.append(.cancel())
                return ActionSheet(
                    title: Text("Delete contact?"),
                    buttons: sheetButtons
                )
            case let .confirmDeleteContactActionSheet(contactDeleteMode):
                if contact.ready && contact.active {
                    return ActionSheet(
                        title: Text("Notify contact?\nThis cannot be undone!"),
                        buttons: [
                            .destructive(Text("Delete and notify contact")) { deleteContact(chatDeleteMode: contactDeleteMode.toChatDeleteMode(notify: true)) },
                            .destructive(Text("Delete without notification")) { deleteContact(chatDeleteMode: contactDeleteMode.toChatDeleteMode(notify: false)) },
                            .cancel()
                        ]
                    )
                } else {
                    return ActionSheet(
                        title: Text("Confirm contact deletion.\nThis cannot be undone!"),
                        buttons: [
                            .destructive(Text("Delete")) { deleteContact(chatDeleteMode: contactDeleteMode.toChatDeleteMode(notify: false)) },
                            .cancel()
                        ]
                    )
                }
            }
        }
    }

    private func contactInfoHeader() -> some View {
        VStack {
            let cInfo = chat.chatInfo
            ChatInfoImage(chat: chat, size: 192, color: Color(uiColor: .tertiarySystemFill))
                .padding(.top, 12)
                .padding()
            if contact.verified {
                (
                    Text(Image(systemName: "checkmark.shield"))
                        .foregroundColor(.secondary)
                        .font(.title2)
                    + Text(" ")
                    + Text(contact.profile.displayName)
                        .font(.largeTitle)
                )
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.bottom, 2)
            } else {
                Text(contact.profile.displayName)
                    .font(.largeTitle)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.bottom, 2)
            }
            if cInfo.fullName != "" && cInfo.fullName != cInfo.displayName && cInfo.fullName != contact.profile.displayName {
                Text(cInfo.fullName)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func localAliasTextEdit() -> some View {
        TextField("Set contact name…", text: $localAlias)
            .disableAutocorrection(true)
            .focused($aliasTextFieldFocused)
            .submitLabel(.done)
            .onChange(of: aliasTextFieldFocused) { focused in
                if !focused {
                    setContactAlias()
                }
            }
            .onSubmit {
                setContactAlias()
            }
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)
    }

    private func setContactAlias() {
        Task {
            do {
                if let contact = try await apiSetContactAlias(contactId: chat.chatInfo.apiId, localAlias: localAlias) {
                    await MainActor.run {
                        chatModel.updateContact(contact)
                    }
                }
            } catch {
                logger.error("setContactAlias error: \(responseError(error))")
            }
        }
    }

    // when contact is a "contact card"
    private func connectButton() -> some View {
        InfoViewActionButtonLayout(image: "message.fill", title: "connect")
            .onTapGesture {
                showConnectContactViaAddressDialog = true
            }
            .confirmationDialog("Connect with \(contact.chatViewName)", isPresented: $showConnectContactViaAddressDialog, titleVisibility: .visible) {
                Button("Use current profile") { connectContactViaAddress_(contact, false) }
                Button("Use new incognito profile") { connectContactViaAddress_(contact, true) }
            }
    }

    private func connectContactViaAddress_(_ contact: Contact, _ incognito: Bool) {
        Task {
            let ok = await connectContactViaAddress(contact.contactId, incognito)
            if ok {
                await MainActor.run {
                    if openedFromChatView {
                        dismiss()
                    } else {
                        if contact.chatDeleted {
                            var updatedContact = contact
                            updatedContact.chatDeleted = false
                            chatModel.updateContact(updatedContact)
                        }
                        chatModel.chatId = chat.id
                    }
                }
            }
        }
    }

    private func openButton() -> some View {
        InfoViewActionButtonLayout(image: "message.fill", title: "open")
            .onTapGesture {
                if openedFromChatView {
                    dismiss()
                } else {
                    chatModel.chatId = chat.id
                }
            }
    }

    // TODO show keyboard
    private func messageButton() -> some View {
        InfoViewActionButtonLayout(image: "message.fill", title: "message")
            .onTapGesture {
                if openedFromChatView {
                    dismiss()
                } else {
                    if contact.chatDeleted {
                        var updatedContact = contact
                        updatedContact.chatDeleted = false
                        chatModel.updateContact(updatedContact)
                    }
                    chatModel.chatId = chat.id
                }
            }
            .disabled(!contact.sendMsgEnabled)
    }

    private func callButton() -> some View {
        InfoViewActionButtonLayout(image: "phone.fill", title: "call")
            .onTapGesture {
                CallController.shared.startCall(contact, .audio)
            }
            .disabled(!contact.ready || !contact.active || !contact.mergedPreferences.calls.enabled.forUser || chatModel.activeCall != nil)
    }

    private func videoButton() -> some View {
        InfoViewActionButtonLayout(image: "video.fill", title: "video")
            .onTapGesture {
                CallController.shared.startCall(contact, .video)
            }
            .disabled(!contact.ready || !contact.active || !contact.mergedPreferences.calls.enabled.forUser || chatModel.activeCall != nil)
    }

    private func verifyCodeButton(_ code: String) -> some View {
        NavigationLink {
            VerifyCodeView(
                displayName: contact.displayName,
                connectionCode: code,
                connectionVerified: contact.verified,
                verify: { code in
                    if let r = apiVerifyContact(chat.chatInfo.apiId, connectionCode: code) {
                        let (verified, existingCode) = r
                        contact.activeConn?.connectionCode = verified ? SecurityCode(securityCode: existingCode, verifiedAt: .now) : nil
                        connectionCode = existingCode
                        DispatchQueue.main.async {
                            chat.chatInfo = .direct(contact: contact)
                        }
                        return r
                    }
                    return nil
                }
            )
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Security code")
        } label: {
            Label(
                contact.verified ? "View security code" : "Verify security code",
                systemImage: contact.verified ? "checkmark.shield" : "shield"
            )
        }
    }

    private func contactPreferencesButton() -> some View {
        NavigationLink {
            ContactPreferencesView(
                contact: $contact,
                featuresAllowed: contactUserPrefsToFeaturesAllowed(contact.mergedPreferences),
                currentFeaturesAllowed: contactUserPrefsToFeaturesAllowed(contact.mergedPreferences)
            )
            .navigationBarTitle("Contact preferences")
            .navigationBarTitleDisplayMode(.large)
        } label: {
            Label("Contact preferences", systemImage: "switch.2")
        }
    }

    private func sendReceiptsOption() -> some View {
        Picker(selection: $sendReceipts) {
            ForEach([.yes, .no, .userDefault(sendReceiptsUserDefault)]) { (opt: SendReceipts) in
                Text(opt.text)
            }
        } label: {
            Label("Send receipts", systemImage: "checkmark.message")
        }
        .frame(height: 36)
        .onChange(of: sendReceipts) { _ in
            setSendReceipts()
        }
    }

    private func setSendReceipts() {
        var chatSettings = chat.chatInfo.chatSettings ?? ChatSettings.defaults
        chatSettings.sendRcpts = sendReceipts.bool()
        updateChatSettings(chat, chatSettings: chatSettings)
    }

    private func synchronizeConnectionButton() -> some View {
        Button {
            syncContactConnection(force: false)
        } label: {
            Label("Fix connection", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                .foregroundColor(.orange)
        }
    }

    private func synchronizeConnectionButtonForce() -> some View {
        Button {
            alert = .syncConnectionForceAlert
        } label: {
            Label("Renegotiate encryption", systemImage: "exclamationmark.triangle")
                .foregroundColor(.red)
        }
    }

    private func networkStatusRow() -> some View {
        HStack {
            Text("Network status")
            Image(systemName: "info.circle")
                .foregroundColor(.accentColor)
                .font(.system(size: 14))
            Spacer()
            Text(chatModel.contactNetworkStatus(contact).statusString)
                .foregroundColor(.secondary)
            serverImage()
        }
    }

    private func serverImage() -> some View {
        let status = chatModel.contactNetworkStatus(contact)
        return Image(systemName: status.imageName)
            .foregroundColor(status == .connected ? .green : .secondary)
            .font(.system(size: 12))
    }

    private func deleteContactButton() -> some View {
        Button(role: .destructive) {
            actionSheet = .deleteContactActionSheet
        } label: {
            Label("Delete contact", systemImage: "person.badge.minus")
                .foregroundColor(Color.red)
        }
    }

    private func clearChatButton() -> some View {
        Button() {
            alert = .clearChatAlert
        } label: {
            Label("Clear conversation", systemImage: "gobackward")
                .foregroundColor(Color.orange)
        }
    }

    private func deleteContact(chatDeleteMode: ChatDeleteMode) {
        Task {
            do {
                let ct = try await apiDeleteContact(id: chat.chatInfo.apiId, chatDeleteMode: chatDeleteMode)
                await MainActor.run {
                    dismiss()
                    chatModel.chatId = nil
                    switch chatDeleteMode {
                    case .full:
                        chatModel.removeChat(chat.chatInfo.id)
                    case .entity:
                        chatModel.updateContact(ct)
                        // dismissing sheet when opened from ChatView closes deleteContactNotice alert,
                        // also it makes less sense to show this alert as user is already in Chats tab
                        if showDeleteContactNotice && !openedFromChatView {
                            alert = .deleteContactNotice
                        }
                    case .messages:
                        logger.warning("ChatInfoView deleteContact case .messages should be unreachable")
                        chatModel.removeChat(chat.chatInfo.id)
                        chatModel.addChat(Chat(
                            chatInfo: .direct(contact: ct),
                            chatItems: []
                        ))
                    }
                }
            } catch let error {
                logger.error("ChatInfoView deleteContact apiDeleteContact error: \(responseError(error))")
                let a = getErrorAlert(error, "Error deleting contact")
                await MainActor.run {
                    alert = .error(title: a.title, error: a.message)
                }
            }
        }
    }

    private func clearChatAlert() -> Alert {
        Alert(
            title: Text("Clear conversation?"),
            message: Text("All messages will be deleted - this cannot be undone! The messages will be deleted ONLY for you."),
            primaryButton: .destructive(Text("Clear")) {
                Task {
                    await clearChat(chat)
                    await MainActor.run { dismiss() }
                }
            },
            secondaryButton: .cancel()
        )
    }

    private func networkStatusAlert() -> Alert {
        Alert(
            title: Text("Network status"),
            message: Text(chatModel.contactNetworkStatus(contact).statusExplanation)
        )
    }

    private func switchContactAddress() {
        Task {
            do {
                let stats = try apiSwitchContact(contactId: contact.apiId)
                connectionStats = stats
                await MainActor.run {
                    chatModel.updateContactConnectionStats(contact, stats)
                    dismiss()
                }
            } catch let error {
                logger.error("switchContactAddress apiSwitchContact error: \(responseError(error))")
                let a = getErrorAlert(error, "Error changing address")
                await MainActor.run {
                    alert = .error(title: a.title, error: a.message)
                }
            }
        }
    }

    private func abortSwitchContactAddress() {
        Task {
            do {
                let stats = try apiAbortSwitchContact(contact.apiId)
                connectionStats = stats
                await MainActor.run {
                    chatModel.updateContactConnectionStats(contact, stats)
                }
            } catch let error {
                logger.error("abortSwitchContactAddress apiAbortSwitchContact error: \(responseError(error))")
                let a = getErrorAlert(error, "Error aborting address change")
                await MainActor.run {
                    alert = .error(title: a.title, error: a.message)
                }
            }
        }
    }

    private func syncContactConnection(force: Bool) {
        Task {
            do {
                let stats = try apiSyncContactRatchet(contact.apiId, force)
                connectionStats = stats
                await MainActor.run {
                    chatModel.updateContactConnectionStats(contact, stats)
                    dismiss()
                }
            } catch let error {
                logger.error("syncContactConnection apiSyncContactRatchet error: \(responseError(error))")
                let a = getErrorAlert(error, "Error synchronizing connection")
                await MainActor.run {
                    alert = .error(title: a.title, error: a.message)
                }
            }
        }
    }

    private func deleteContactNotice(_ contact: Contact) -> Alert {
        return Alert(
            title: Text("Contact deleted!"),
            message: Text("You can still view conversation with \(contact.displayName) in the Chats tab."),
            primaryButton: .default(Text("Don't show again")) {
                showDeleteContactNotice = false
            },
            secondaryButton: .default(Text("Ok"))
        )
    }
}

struct InfoViewActionButtonLayout: View {
    var image: String
    var title: LocalizedStringKey

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: image)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
            Text(title)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundColor(.accentColor)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12.0)
        .frame(width: 90, height: 60)
    }
}

func switchAddressAlert(_ switchAddress: @escaping () -> Void) -> Alert {
    Alert(
        title: Text("Change receiving address?"),
        message: Text("Receiving address will be changed to a different server. Address change will complete after sender comes online."),
        primaryButton: .default(Text("Change"), action: switchAddress),
        secondaryButton: .cancel()
    )
}

func abortSwitchAddressAlert(_ abortSwitchAddress: @escaping () -> Void) -> Alert {
    Alert(
        title: Text("Abort changing address?"),
        message: Text("Address change will be aborted. Old receiving address will be used."),
        primaryButton: .destructive(Text("Abort"), action: abortSwitchAddress),
        secondaryButton: .cancel()
    )
}

func syncConnectionForceAlert(_ syncConnectionForce: @escaping () -> Void) -> Alert {
    Alert(
        title: Text("Renegotiate encryption?"),
        message: Text("The encryption is working and the new encryption agreement is not required. It may result in connection errors!"),
        primaryButton: .destructive(Text("Renegotiate"), action: syncConnectionForce),
        secondaryButton: .cancel()
    )
}

struct ChatInfoView_Previews: PreviewProvider {
    static var previews: some View {
        ChatInfoView(
            openedFromChatView: true,
            chat: Chat(chatInfo: ChatInfo.sampleData.direct, chatItems: []),
            contact: Contact.sampleData,
            localAlias: ""
        )
    }
}
