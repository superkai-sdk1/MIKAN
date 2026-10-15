import PhotosUI
import SwiftUI

/// Uploads a picked library image as JPEG and returns its `/uploads/…` path.
enum ServiceImageUpload {
    static func upload(_ item: PhotosPickerItem, api: APIClient) async throws -> String {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw ImagePreparerError.unreadable
        }
        let jpeg = try await ImagePreparer.jpegInBackground(from: data)
        return try await api.uploadImage(jpegData: jpeg).url
    }
}

// MARK: - Cover

/// The schematic cover: own upload or removal, and what to draw when generating it.
struct ServiceCoverEditorSection: View {
    @Environment(APIClient.self) private var api
    @Binding var imageUrl: String?
    @Binding var imagePrompt: String
    @Binding var isUploading: Bool
    @Binding var errorMessage: String?
    let placeholderSymbol: String

    @State private var pickerItem: PhotosPickerItem?

    private static let thumbnailSize: CGFloat = 84

    var body: some View {
        Section {
            HStack(spacing: 16) {
                ZStack {
                    ProductThumbnail(path: imageUrl, size: Self.thumbnailSize, placeholderSymbol: placeholderSymbol)
                    if isUploading {
                        ProgressView()
                            .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
                            .background(.ultraThinMaterial, in: .rect(cornerRadius: Self.thumbnailSize * 0.22))
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    // The picker label closure is Sendable, so the title is computed outside it.
                    let pickerTitle = imageUrl == nil ? "Загрузить свою" : "Заменить своей"
                    PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                        Label(pickerTitle, systemImage: "photo.on.rectangle")
                    }
                    .disabled(isUploading)
                    if imageUrl != nil {
                        Button("Убрать обложку", systemImage: "trash", role: .destructive) { imageUrl = nil }
                            .disabled(isUploading)
                    }
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 4)
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await upload(item) }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Что нарисовать")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Например: схема прокола хеликса, вид сбоку", text: $imagePrompt, axis: .vertical)
                    .lineLimit(2...6)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Картинка (обложка)")
        } footer: {
            if let message = ServiceLimits.imagePromptMessage(imagePrompt) {
                Text(message).foregroundStyle(.red)
            } else {
                Text("Схематичная картинка услуги: её видно в каталоге и кассе, бот отправляет её клиентам. Сгенерировать картинку ИИ можно в карточке услуги после сохранения — по тексту «Что нарисовать» или по названию и описанию.")
            }
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        isUploading = true
        defer {
            isUploading = false
            pickerItem = nil
        }
        do {
            imageUrl = try await ServiceImageUpload.upload(item, api: api)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.userMessage
        }
    }
}

// MARK: - Work photos

/// Photos of real works: a grid with remove buttons and multi-select upload (up to 12 in total).
struct ServicePhotosEditorSection: View {
    @Environment(APIClient.self) private var api
    @Binding var photos: [String]
    @Binding var isUploading: Bool
    @Binding var errorMessage: String?

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var progress: UploadProgress?

    private static let tileSize: CGFloat = 64
    /// Minimum touch target for the remove button over a tile.
    private static let removeTarget: CGFloat = 44

    private struct UploadProgress: Equatable {
        let done: Int
        let total: Int
    }

    private var remaining: Int { ServiceLimits.remainingPhotos(current: photos.count) }

    var body: some View {
        Section {
            if !photos.isEmpty || progress != nil {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tileSize), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(Array(photos.enumerated()), id: \.element) { index, path in
                        tile(path: path, index: index)
                    }
                    if let progress {
                        uploadingTile(progress)
                    }
                }
                .padding(.vertical, 6)
            }
            let pickerTitle = remaining == 0 ? "Добавлено максимум фото" : "Добавить фото"
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: max(1, remaining),
                selectionBehavior: .ordered,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label(pickerTitle, systemImage: "photo.badge.plus")
            }
            .disabled(isUploading || remaining == 0)
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await upload(items) }
            }
        } header: {
            HStack {
                Text("Фото работ")
                Spacer()
                Text("\(photos.count) из \(ServiceLimits.maxPhotos)").monospacedDigit()
            }
        } footer: {
            Text("Фото готовых работ для карточки услуги — до \(ServiceLimits.maxPhotos) штук.")
        }
    }

    private func tile(path: String, index: Int) -> some View {
        ProductThumbnail(path: path, size: Self.tileSize, placeholderSymbol: "photo")
            .overlay(alignment: .topTrailing) {
                Button {
                    photos = photos.filter { $0 != path }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .padding(3)
                        .frame(width: Self.removeTarget, height: Self.removeTarget, alignment: .topTrailing)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Удалить фото \(index + 1)")
            }
    }

    private func uploadingTile(_ progress: UploadProgress) -> some View {
        VStack(spacing: 6) {
            ProgressView()
            Text("\(min(progress.done + 1, progress.total)) из \(progress.total)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(width: Self.tileSize, height: Self.tileSize)
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: Self.tileSize * 0.22))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Загрузка фото \(min(progress.done + 1, progress.total)) из \(progress.total)")
    }

    /// Uploads the picked photos one by one; keeps the ones that made it when some fail.
    private func upload(_ items: [PhotosPickerItem]) async {
        let batch = Array(items.prefix(remaining))
        pickerItems = []
        guard !batch.isEmpty else { return }
        isUploading = true
        progress = UploadProgress(done: 0, total: batch.count)
        defer {
            isUploading = false
            progress = nil
        }
        var failures = 0
        var lastError: String?
        for (index, item) in batch.enumerated() {
            guard ServiceLimits.remainingPhotos(current: photos.count) > 0 else { break }
            do {
                let path = try await ServiceImageUpload.upload(item, api: api)
                photos = photos + [path]
            } catch is CancellationError {
                return
            } catch {
                failures += 1
                lastError = error.userMessage
            }
            progress = UploadProgress(done: index + 1, total: batch.count)
        }
        if failures > 0 {
            errorMessage = Self.failureMessage(failures: failures, total: batch.count, lastError: lastError)
        }
    }

    private static func failureMessage(failures: Int, total: Int, lastError: String?) -> String {
        let reason = lastError ?? "Попробуйте ещё раз."
        guard total > 1 else { return reason }
        return "Не удалось загрузить \(failures) из \(total) фото. \(reason)"
    }
}
