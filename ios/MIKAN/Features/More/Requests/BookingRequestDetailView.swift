import SwiftUI

struct BookingRequestDetailView: View {
    @Environment(APIClient.self) private var api
    @Environment(ScheduleStore.self) private var schedule
    @Environment(\.openURL) private var openURL

    @State private var request: BookingRequest
    let onChange: (BookingRequest) -> Void

    @State private var appointmentDraft: AppointmentDraft?
    @State private var confirmsReject = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var successCount = 0

    init(request: BookingRequest, onChange: @escaping (BookingRequest) -> Void) {
        _request = State(initialValue: request)
        self.onChange = onChange
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    StatusBadge(text: request.status.singularTitle, color: request.status.color)
                    Text(request.displayName).font(.title2.weight(.bold))
                    Text("Получена \(DateText.dateTime(request.createdAt))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section("Заявка") {
                if let service = request.serviceName.nonEmpty {
                    LabeledContent("Услуга", value: service)
                }
                if let time = request.preferredTime.nonEmpty {
                    LabeledContent("Удобное время", value: time)
                }
                if let comment = request.comment.nonEmpty {
                    Text(comment)
                }
            }
            Section("Контакты") {
                if let client = request.client {
                    NavigationLink {
                        ClientDetailView(clientId: client.id)
                    } label: {
                        Label(client.name, systemImage: "person.crop.circle")
                    }
                }
                if let phone = request.phone.nonEmpty {
                    Button {
                        if let url = PhoneText.callURL(phone) { openURL(url) }
                    } label: {
                        Label(PhoneText.display(phone), systemImage: "phone.fill")
                    }
                }
                if let chatId = request.chatId {
                    NavigationLink {
                        ChatResolverView(title: request.displayName, lookup: .telegramChat(id: chatId))
                    } label: {
                        Label("Переписка с ботом", systemImage: "bubble.left.and.bubble.right")
                    }
                }
            }
            Section {
                Button {
                    appointmentDraft = draft()
                } label: {
                    Label("Создать запись", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if request.status == .new {
                Section {
                    Button("Отметить обработанной", systemImage: "checkmark.circle") { setStatus(.processed) }
                    Button("Отклонить", systemImage: "xmark.circle", role: .destructive) { confirmsReject = true }
                }
            } else {
                Section {
                    Button("Вернуть в новые", systemImage: "arrow.uturn.backward") { setStatus(.new) }
                }
            }
        }
        .disabled(isWorking)
        .navigationTitle("Заявка")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $appointmentDraft) { draft in
            AppointmentEditorView(draft: draft) { saved in
                schedule.upsert(saved)
                if request.status == .new { setStatus(.processed) }
            }
        }
        .confirmationDialog("Отклонить заявку?", isPresented: $confirmsReject, titleVisibility: .visible) {
            Button("Отклонить", role: .destructive) { setStatus(.rejected) }
            Button("Отмена", role: .cancel) {}
        }
        .errorAlert($errorMessage)
        .sensoryFeedback(.success, trigger: successCount)
    }

    private func draft() -> AppointmentDraft {
        let details = [
            request.serviceName.nonEmpty.map { "Услуга: \($0)" },
            request.preferredTime.nonEmpty.map { "Удобное время: \($0)" },
            request.comment.nonEmpty.map { "Комментарий: \($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        let suggestion = request.client == nil
            ? ClientSuggestion(name: request.contactName ?? "", phone: request.phone ?? "")
            : nil
        return AppointmentDraft.new(
            day: .now,
            client: request.client,
            notes: details.isEmpty ? "" : "Заявка из Telegram\n\(details)",
            suggestion: suggestion
        )
    }

    private func setStatus(_ status: BookingStatus) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                request = try await api.setBookingRequestStatus(id: request.id, status)
                onChange(request)
                successCount += 1
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BookingRequestDetailView(request: PreviewData.bookingRequest) { _ in }
    }
    .previewEnvironment()
}
#endif
