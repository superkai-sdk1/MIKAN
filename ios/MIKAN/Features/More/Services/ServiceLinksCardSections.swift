import SwiftUI

/// «Совместимые украшения» of the service card: a strip of the linked pieces; a tap opens the piece.
struct ServiceJewelryCardSection: View {
    let jewelryIds: [Int]
    /// Jewelry and consumables of the warehouse (`APIClient.serviceLinkProducts`).
    let stock: Remote<[Product]>
    let retry: () async -> Void
    let onOpen: (Product) -> Void

    private var linked: [Product] { ServiceLinkedProducts.resolve(jewelryIds, in: stock.value ?? []) }

    var body: some View {
        Section {
            if jewelryIds.isEmpty {
                Text("Не выбраны. Добавьте их в редакторе — бот будет предлагать украшения к этой процедуре.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ServiceStockState(stock: stock, retry: retry) {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(linked) { product in
                                Button {
                                    onOpen(product)
                                } label: {
                                    JewelryLinkTile(product: product)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Открыть карточку украшения")
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .scrollIndicators(.hidden)
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                }
            }
        } header: {
            ServiceCountHeader(title: "Совместимые украшения", count: jewelryIds.count)
        } footer: {
            if !jewelryIds.isEmpty {
                Text("Бот предлагает эти украшения клиентам, которые спрашивают про процедуру.")
            }
        }
    }
}

/// «Расход на процедуру» of the service card: what one procedure takes from the warehouse.
struct ServiceNormsCardSection: View {
    let consumables: [ServiceConsumable]
    let stock: Remote<[Product]>
    let retry: () async -> Void

    var body: some View {
        Section {
            if consumables.isEmpty {
                Text("Норма не задана — при завершении записи расходники по этой услуге сами не спишутся.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ServiceStockState(stock: stock, retry: retry) {
                    ForEach(consumables, id: \.productId) { norm in
                        row(norm, product: stock.value?.first { $0.id == norm.productId })
                    }
                }
            }
        } header: {
            ServiceCountHeader(title: "Расход на процедуру", count: consumables.count)
        } footer: {
            if !consumables.isEmpty {
                Text("Списывается со склада при завершении записи; расходники «есть / нет» только отмечаются.")
            }
        }
    }

    private func row(_ norm: ServiceConsumable, product: Product?) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(product?.name ?? "Расходник не найден")
                    .foregroundStyle(product == nil ? .secondary : .primary)
                if let product {
                    ProductStockLine(product: product)
                }
            }
            Spacer(minLength: 8)
            if product?.isPresenceTracked == true {
                StatusBadge(text: "используется", color: .secondary)
            } else {
                Text(ServiceLinkText.norm(quantity: norm.quantity, product: product))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
