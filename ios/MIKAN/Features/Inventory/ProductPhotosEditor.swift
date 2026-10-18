import PhotosUI
import SwiftUI

/// Product photos: a grid where the first photo is the cover, multi-select upload (up to 10),
/// removal and reordering from the tile's menu.
struct ProductPhotosEditorSection: View {
    @Environment(APIClient.self) private var api
    @Binding var draft: ProductDraft
    @Binding var isUploading: Bool
    @Binding var errorMessage: String?

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var progress: UploadProgress?

    private static let tileSize: CGFloat = 76
    /// Minimum touch target for the remove button over a tile.
    private static let removeTarget: CGFloat = 44

    private struct UploadProgress: Equatable {
        let done: Int
        let total: Int
    }

    var body: some View {
        Section {
            if !draft.photos.isEmpty || progress != nil {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tileSize), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(Array(draft.photos.enumerated()), id: \.element) { index, path in
                        tile(path: path, index: index)
                    }
                    if let progress {
                        uploadingTile(progress)
                    }
                }
                .padding(.vertical, 6)
            }
            let remaining = draft.remainingPhotos
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
                Text("Фото")
                Spacer()
                Text("\(draft.photos.count) из \(ProductLimits.maxPhotos)").monospacedDigit()
            }
        } footer: {
            if let message = draft.photosMessage {
                Text(message).foregroundStyle(.red)
            } else {
                Text("Первое фото — обложка: его видно на складе и в кассе, его отправляет бот. Удерживайте фото, чтобы сделать его обложкой или переставить.")
            }
        }
    }

    private func tile(path: String, index: Int) -> some View {
        ProductThumbnail(path: path, size: Self.tileSize, placeholderSymbol: "photo")
            .overlay(alignment: .bottom) {
                if index == 0 {
                    Text("Обложка")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55))
                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Self.tileSize * 0.22, bottomTrailingRadius: Self.tileSize * 0.22))
                }
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    draft = draft.removingPhoto(path)
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
            .contextMenu {
                Button("Сделать обложкой", systemImage: "star") { draft = draft.makingCover(path) }
                    .disabled(index == 0)
                Button("Левее", systemImage: "arrow.left") { draft = draft.movingPhoto(path, by: -1) }
                    .disabled(index == 0)
                Button("Правее", systemImage: "arrow.right") { draft = draft.movingPhoto(path, by: 1) }
                    .disabled(index >= draft.photos.count - 1)
                Divider()
                Button("Удалить", systemImage: "trash", role: .destructive) { draft = draft.removingPhoto(path) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(index == 0 ? "Обложка" : "Фото \(index + 1)")
            .accessibilityActions {
                if index > 0 {
                    Button("Сделать обложкой") { draft = draft.makingCover(path) }
                }
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
        let batch = Array(items.prefix(draft.remainingPhotos))
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
            guard draft.remainingPhotos > 0 else { break }
            do {
                let path = try await ServiceImageUpload.upload(item, api: api)
                draft = draft.addingPhotos([path])
            } catch is CancellationError {
                return
            } catch {
                failures += 1
                lastError = error.userMessage
            }
            progress = UploadProgress(done: index + 1, total: batch.count)
        }
        if failures > 0 {
            let reason = lastError ?? "Попробуйте ещё раз."
            errorMessage = batch.count > 1 ? "Не удалось загрузить \(failures) из \(batch.count) фото. \(reason)" : reason
        }
    }
}
