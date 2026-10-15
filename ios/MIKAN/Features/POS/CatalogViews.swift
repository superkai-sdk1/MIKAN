import SwiftUI

/// Jewelry tile in the POS catalog. Tap adds one to the cart.
struct ProductTile: View {
    let product: Product
    let inCart: Int
    let onAdd: () -> Void

    private var isAvailable: Bool { product.quantity > 0 }

    var body: some View {
        Button(action: onAdd) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    ProductThumbnail(path: product.photoUrl, size: 140)
                        .frame(maxWidth: .infinity)
                    if inCart > 0 {
                        Text("\(inCart)")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .frame(minWidth: 26, minHeight: 26)
                            .background(Color.accentColor, in: .circle)
                            .padding(6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(product.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2, reservesSpace: true)
                if !product.detailLine.isEmpty {
                    Text(product.detailLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack {
                    MoneyText(product.price)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    Text(isAvailable ? "\(product.quantity) \(product.unitLabel)" : "Нет")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(product.lowStock ? Color.red : Color.secondary)
                }
            }
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
            .contentShape(.rect(cornerRadius: 20))
            .opacity(isAvailable ? 1 : 0.5)
            .animation(.snappy, value: inCart)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .accessibilityLabel("\(product.name), \(Money.format(product.price)), осталось \(product.quantity)")
        .accessibilityHint(isAvailable ? "Добавить в корзину" : "Нет в наличии")
        .accessibilityValue(inCart > 0 ? "В корзине: \(inCart)" : "")
    }
}

/// Horizontal category filter.
struct CategoryChips: View {
    let categories: [String]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(title: "Все", value: nil)
                ForEach(categories, id: \.self) { category in
                    chip(title: category, value: category)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func chip(title: String, value: String?) -> some View {
        let isSelected = selection == value
        Button(title) {
            withAnimation(.snappy) { selection = value }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .modifier(ChipStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ChipStyle: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

/// Floating glass cluster: «Услуга» and the cart. The compact cart button morphs into the checkout bar.
struct CartBar: View {
    @Environment(CartStore.self) private var cart
    let onAddService: () -> Void
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: onAddService) {
                    Label("Услуга", systemImage: "plus")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .frame(height: 52)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("service", in: glassNamespace)
                .accessibilityHint("Добавить услугу из каталога или свою")

                Spacer(minLength: 0)

                if cart.isEmpty {
                    Image(systemName: "cart")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(width: 52, height: 52)
                        .glassEffect(.regular, in: .circle)
                        .glassEffectID("cart", in: glassNamespace)
                        .accessibilityLabel("Корзина пуста")
                } else {
                    Button { cart.isCheckoutPresented = true } label: { expandedCart }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)
                        .glassEffectID("cart", in: glassNamespace)
                        .accessibilityLabel("Корзина: \(Plural.count(cart.itemCount, one: "позиция", few: "позиции", many: "позиций")), \(Money.format(cart.total))")
                        .accessibilityHint("Оформить продажу")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: cart.isEmpty)
    }

    private var expandedCart: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "cart.fill").font(.headline)
                Text("\(cart.itemCount)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 4)
                    .background(.white, in: .capsule)
                    .offset(x: 10, y: -8)
            }
            Text(Money.format(cart.total))
                .font(.headline)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(cart.total)))
            Spacer(minLength: 8)
            Text("Оформить").font(.headline)
            Image(systemName: "chevron.right").font(.subheadline.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .contentShape(.capsule)
    }
}

#if DEBUG
#Preview("Плитки") {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
        ForEach(PreviewData.products) { product in
            ProductTile(product: product, inCart: product.id == 1 ? 2 : 0) {}
        }
    }
    .padding()
    .previewEnvironment()
}
#endif
