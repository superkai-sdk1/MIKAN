import SwiftUI

/// What the full-screen viewer shows: a set of pictures and the one to start from.
struct ServicePhotoViewerItem: Identifiable {
    let id = UUID()
    let paths: [String]
    let index: Int
}

/// Full-screen pictures with swipe paging.
struct ServicePhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var api
    let paths: [String]
    @State private var selection: Int

    init(item: ServicePhotoViewerItem) {
        paths = item.paths
        _selection = State(initialValue: min(max(0, item.index), max(0, item.paths.count - 1)))
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(Array(paths.enumerated()), id: \.offset) { index, path in
                    page(path: path)
                        .tag(index)
                        .accessibilityLabel("Фото \(index + 1) из \(paths.count)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: paths.count > 1 ? .always : .never))
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(paths.count > 1 ? "\(selection + 1) из \(paths.count)" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func page(path: String) -> some View {
        AsyncImage(url: api.mediaURL(for: path), transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            case .failure:
                ContentUnavailableView("Не удалось загрузить фото", systemImage: "photo.badge.exclamationmark")
            default:
                ProgressView().controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
