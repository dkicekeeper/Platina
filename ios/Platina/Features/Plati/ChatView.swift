import SwiftUI
import PhotosUI
import DesignTokens
import DesignSupport
import DesignComponents
import PlatinaStore
import PlatinaAssistant

/// A conversation with Plati (docs/PLAN.md §3.6): the messages, the "thinking" line while a tool
/// runs, the reply as it streams, suggestions on an empty chat, the field.
struct ChatView: View {
    let thread: ChatThread
    var suggestions: [String] = []

    @State private var draft = ""
    @State private var photoItem: PhotosPickerItem?
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.md) {
                    if thread.messages.isEmpty, !thread.isResponding {
                        intro
                    }
                    ForEach(thread.messages) { message in
                        row(message)
                            .id(message.id)
                    }
                    if thread.isResponding {
                        responding
                            .id("responding")
                    }
                }
                .screenPadding()
                .padding(.vertical, AppSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .onChange(of: thread.messages.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: thread.streamingText) { _, _ in scrollToEnd(proxy) }
            .onAppear { scrollToEnd(proxy, animated: false) }
        }
        .safeAreaBar(edge: .bottom) {
            MessageComposer(
                text: $draft,
                placeholder: thread.isAvailable ? String(localized: "plati.placeholder") : String(localized: "plati.offline.placeholder"),
                isSending: thread.isResponding,
                focus: $isFocused,
                leading: {
                    // "Where am I?": a photo of the TV or a PS5 screenshot.
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        MessageComposerAccessory(systemImage: "camera.viewfinder")
                    }
                    .accessibilityLabel(Text("plati.photo.attach"))
                },
                onSend: {
                    let text = draft
                    draft = ""
                    Task { await thread.send(text) }
                }
            )
            .disabled(!thread.isAvailable)
            .screenPadding()
            .padding(.bottom, AppSpacing.sm)
        }
        .background(AppColors.Background.base)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            draft = ""
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let photo = ChatPhoto.prepare(data) else { return }
                await thread.send(typed.isEmpty ? String(localized: "plati.photo.whereAmI") : typed, photo: photo)
            }
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                if let data = message.photo, let image = UIImage(data: data) {
                    PhotoTile(image: image)
                        .accessibilityLabel(Text("plati.photo.sent"))
                }
                MessageBubble(
                    message.text,
                    role: .outgoing,
                    time: message.date,
                    failure: message.failed ? failureText : nil,
                    onRetry: message.failed ? { Task { await thread.retry() } } : nil
                )
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .transition(.messageBubble(.outgoing))
        case .event:
            VStack(spacing: AppSpacing.xs) {
                ConversationDivider(eventTitle(message.text), systemImage: "gamecontroller")
                if message.failed {
                    InlineRetry(text: failureText) { Task { await thread.retry() } }
                }
            }
        case .assistant:
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                if !message.text.isEmpty {
                    MessageBubble(markdown: message.text, role: .incoming, time: message.date)
                }
                ForEach(Array(message.cards.enumerated()), id: \.offset) { _, card in
                    ChatCardView(card: card)
                }
                // Quick replies under the last reply only, while nothing else is going on.
                if message.id == thread.messages.last?.id, !thread.isResponding, !message.replies.isEmpty {
                    SuggestionChips(message.replies, systemImage: "arrowshape.turn.up.left") { reply in
                        Task { await thread.send(reply) }
                    }
                }
            }
            .transition(.messageBubble(.incoming))
        }
    }

    @ViewBuilder
    private var responding: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if thread.streamingText.isEmpty {
                HStack(spacing: AppSpacing.sm) {
                    ParticleCreature(mood: thread.step == nil ? .thinking : .working(progress: 0.5), style: .compact)
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                    Text(stepText)
                        .font(AppTypography.caption)
                        .thinkingShimmer()
                }
                TypingIndicator()
                    .transition(.popIn)
            } else {
                MessageBubble(markdown: thread.streamingText, role: .incoming)
            }
        }
    }

    private var intro: some View {
        VStack(spacing: AppSpacing.lg) {
            ParticleCreature(mood: .happy, style: .hero, isInteractive: true)
                .frame(width: 180, height: 180)
                .accessibilityHidden(true)
            Text("plati.intro")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.Text.secondary)
                .multilineTextAlignment(.center)
            if thread.isAvailable, !suggestions.isEmpty {
                SuggestionChips(suggestions, systemImage: "sparkles", layout: .wrap) { suggestion in
                    Task { await thread.send(suggestion) }
                }
            }
            if !thread.isAvailable {
                StatusBanner(String(localized: "plati.offline.message"), status: .neutral, systemImage: "wrench.and.screwdriver")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.xl)
    }

    // MARK: Texts

    private var stepText: String {
        switch thread.step {
        case nil: String(localized: "plati.step.thinking")
        case "web_search": String(localized: "plati.step.search")
        case "get_guide": String(localized: "plati.step.guide")
        case "list_trophies": String(localized: "plati.step.trophies")
        case "get_game", "list_games": String(localized: "plati.step.games")
        case "get_sessions", "get_current_session": String(localized: "plati.step.sessions")
        case "set_session_goals": String(localized: "plati.step.goals")
        case "get_walkthrough", "get_chapter": String(localized: "plati.step.walkthrough")
        case "show_checklist", "show_step", "show_trophies", "show_warning", "suggest_replies": String(localized: "plati.step.cards")
        default: String(localized: "plati.step.working")
        }
    }

    private var failureText: String {
        switch thread.failure {
        case "quota": String(localized: "plati.error.quota")
        case "region_unavailable": String(localized: "plati.error.region")
        case "disabled": String(localized: "plati.error.disabled")
        case "not_configured": String(localized: "plati.offline.message")
        case "attest": String(localized: "plati.error.attest")
        case "offline": String(localized: "plati.error.offline")
        default: String(localized: "plati.error.generic")
        }
    }

    /// The app's own messages read as events: the first line, without the instructions for Plati.
    private func eventTitle(_ text: String) -> String {
        if text.hasPrefix("Начинаю сессию") || text.hasPrefix("I'm starting a session") {
            return String(localized: "plati.event.sessionStarted")
        }
        if text.hasPrefix("Сессия закончена") || text.hasPrefix("The session is over") {
            return String(localized: "plati.event.sessionEnded")
        }
        return text
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let target: String? = thread.isResponding ? "responding" : thread.messages.last?.id
        guard let target else { return }
        if animated {
            withAnimation(AppAnimation.gentleSpring) { proxy.scrollTo(target, anchor: .bottom) }
        } else {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }
}

/// A photo for Plati: at most 1280 px on the long side as a JPEG (what Claude reads well, a few
/// hundred kilobytes), and a small thumbnail the chat keeps.
enum ChatPhoto {
    static func prepare(_ data: Data) -> (image: AssistantImage, thumbnail: Data)? {
        guard let original = UIImage(data: data),
              let full = resized(original, longSide: 1280).jpegData(compressionQuality: 0.6),
              let thumbnail = resized(original, longSide: 360).jpegData(compressionQuality: 0.6) else { return nil }
        return (AssistantImage(data: full, mediaType: "image/jpeg"), thumbnail)
    }

    private static func resized(_ image: UIImage, longSide: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(1, longSide / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

/// A failed event's line with its Retry.
private struct InlineRetry: View {
    let text: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text(verbatim: text)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.Status.negativeText)
            DSButton(String(localized: "common.retry"), appearance: .flat, size: .small, action: action)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The Plati tab: the general conversation.
struct PlatiView: View {
    @Environment(AppModel.self) private var app
    @State private var isConfirmingClear = false

    var body: some View {
        let thread = app.assistant.thread(gameId: nil)
        NavigationStack {
            ChatView(thread: thread, suggestions: [
                String(localized: "plati.suggestion.next"),
                String(localized: "plati.suggestion.fastest"),
                String(localized: "plati.suggestion.close"),
                String(localized: "plati.suggestion.missables"),
            ])
            .navigationTitle(Text("plati.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isConfirmingClear = true
                    } label: {
                        Label(String(localized: "plati.new"), systemImage: "square.and.pencil")
                    }
                    .disabled(thread.messages.isEmpty || thread.isResponding)
                }
            }
            .confirmationDialog(Text("plati.new.confirm"), isPresented: $isConfirmingClear, titleVisibility: .visible) {
                Button(String(localized: "plati.new"), role: .destructive) { thread.clear() }
            }
        }
    }
}

/// A game's conversation with Plati, from the game's screen.
struct GameChatSheet: View {
    let gameId: String
    let gameName: String
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ChatView(thread: app.assistant.thread(gameId: gameId), suggestions: [
                String(localized: "plati.game.suggestion.plan"),
                String(localized: "plati.game.suggestion.missables"),
                String(localized: "plati.game.suggestion.hardest"),
            ])
            .navigationTitle(Text(verbatim: gameName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "session.summary.done")) { dismiss() }
                }
            }
        }
    }
}
