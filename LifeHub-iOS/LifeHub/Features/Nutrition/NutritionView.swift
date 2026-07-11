import SwiftUI

/// Comida: Hoy / Dieta / Macros / Compra / Historial.
struct NutritionView: View {
    @State private var tab = 0

    var body: some View {
        Screen(title: "Comida") {
            Picker("", selection: $tab) {
                Text("Hoy").tag(0)
                Text("Dieta").tag(1)
                Text("Macros").tag(2)
                Text("Compra").tag(3)
            }
            .pickerStyle(.segmented)

            switch tab {
            case 0: TodayList(categories: Category.nutrition)
            case 1: DietView()
            case 2: MacrosView()
            default: ShoppingView()
            }
        }
    }
}

// ── Macros ──────────────────────────────────────────────────────────────────

struct MacrosView: View {
    @State private var day: FoodDay?
    @State private var error: String?
    @State private var weight = Me.fallbackWeight
    @State private var showAdd = false

    var kcalTarget: Int { Me.kcalTarget(weight: weight) }
    var proteinTarget: Double { Me.proteinTarget(weight: weight) }

    var body: some View {
        Group {
            if let error {
                ErrorCard(detail: error) { await load() }
            } else if let day {
                MacroRing(
                    label: "Calorías",
                    value: day.total_kcal,
                    target: Double(kcalTarget),
                    unit: "kcal"
                )
                MacroRing(
                    label: "Proteína",
                    value: day.total_protein,
                    target: proteinTarget,
                    unit: "g"
                )

                CoachCard {
                    try await API.shared.aiMacros(
                        kcal: Int(day.total_kcal),
                        kcalTarget: kcalTarget,
                        protein: day.total_protein,
                        proteinTarget: proteinTarget
                    )
                }

                Button {
                    showAdd = true
                } label: {
                    Label("Añadir comida", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.black)
                }

                if !day.items.isEmpty {
                    SectionHeader(title: "Hoy")
                    ForEach(day.items) { item in
                        HStack {
                            Text(item.name)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(Int(item.kcal)) kcal · \(Int(item.protein)) g")
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                        }
                        .card(padding: 13)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task {
                                    _ = try? await API.shared.removeFood(item.id)
                                    await load()
                                }
                            } label: {
                                Label("Borrar", systemImage: "trash")
                            }
                        }
                    }
                }
            } else {
                SkeletonList()
            }
        }
        .sheet(isPresented: $showAdd) {
            AddFoodSheet { await load() }
                .presentationDetents([.medium])
        }
        .task { await load() }
    }

    func load() async {
        do {
            if let last = try? await API.shared.gymBodyweight().first?.weight { weight = last }
            day = try await API.shared.foodDay()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct MacroRing: View {
    let label: String
    let value: Double
    let target: Double
    let unit: String

    var progress: Double { target > 0 ? min(value / target, 1) : 0 }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Theme.surface2, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(progress * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text("\(Int(value)) de \(Int(target)) \(unit)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .card()
    }
}

struct AddFoodSheet: View {
    let onDone: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Qué has comido", text: $name)
                TextField("Kcal", text: $kcal).keyboardType(.numberPad)
                TextField("Proteína (g)", text: $protein).keyboardType(.decimalPad)
            }
            .navigationTitle("Añadir comida")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        Task {
                            _ = try? await API.shared.addFood(
                                name: name,
                                kcal: Double(kcal) ?? 0,
                                protein: Double(protein.replacingOccurrences(of: ",", with: ".")) ?? 0
                            )
                            await onDone()
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// ── Dieta semanal ───────────────────────────────────────────────────────────

struct DietView: View {
    @State private var toast: String?

    var body: some View {
        LoadView {
            try await API.shared.dietPlan()
        } content: { (plan: DietPlan) in
            Button {
                Task {
                    let r = try? await API.shared.dietAddToShopping()
                    toast = "\(r?.added ?? 0) ingredientes a la compra"
                    Haptics.success()
                }
            } label: {
                Label("Añadir semana a la compra", systemImage: "cart.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Theme.accent)
            }

            if let toast {
                Text(toast)
                    .font(.footnote)
                    .foregroundStyle(Theme.good)
            }

            ForEach(plan.days, id: \.weekday) { day in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(day.weekday)
                            .font(.display(20))
                            .foregroundStyle(day.is_today ? Theme.accent : Theme.ink)
                        if day.is_today {
                            Text("HOY")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.accent.opacity(0.15), in: Capsule())
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    MealRow(label: "Desayuno", dish: day.breakfast, canLog: day.is_today) { logged($0) }
                    MealRow(label: "Comida", dish: day.lunch, canLog: day.is_today) { logged($0) }
                    MealRow(label: "Merienda", dish: day.snack, canLog: day.is_today) { logged($0) }
                    MealRow(label: "Cena", dish: day.dinner, canLog: day.is_today) { logged($0) }
                }
                .card()
            }
        }
    }

    func logged(_ dish: String) {
        toast = "\(dish) apuntado en macros"
        Haptics.success()
    }
}

struct MealRow: View {
    let label: String
    let dish: String
    let canLog: Bool
    let onLogged: (String) -> Void

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: 76, alignment: .leading)
            Text(dish)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
            Spacer()
            if canLog {
                Button {
                    Task {
                        _ = try? await API.shared.dietLogMeal(dish)
                        onLogged(dish)
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }
}

// ── Lista de la compra ──────────────────────────────────────────────────────

struct ShoppingView: View {
    @State private var items: [ShopItem]?
    @State private var error: String?
    @State private var newItem = ""

    var body: some View {
        Group {
            if let error {
                ErrorCard(detail: error) { await load() }
            } else if let items {
                HStack {
                    TextField("Añadir…", text: $newItem)
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.ink)
                        .onSubmit { Task { await add() } }
                    Button {
                        Task { await add() }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                            .foregroundStyle(Theme.accent)
                    }
                    .disabled(newItem.isEmpty)
                }

                if items.isEmpty {
                    EmptyState(text: "Lista vacía.")
                }

                ForEach(items) { item in
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                _ = try? await API.shared.shoppingToggle(item.id)
                                Haptics.light()
                                await load()
                            }
                        } label: {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(item.done ? Theme.good : Theme.muted)
                        }
                        Text(item.text)
                            .strikethrough(item.done)
                            .foregroundStyle(item.done ? Theme.muted : Theme.ink)
                        Spacer()
                    }
                    .card(padding: 12)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task {
                                _ = try? await API.shared.shoppingRemove(item.id)
                                await load()
                            }
                        } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
                }

                if items.contains(where: \.done) {
                    Button("Quitar comprados") {
                        Task {
                            _ = try? await API.shared.shoppingClearDone()
                            await load()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                }
            } else {
                SkeletonList()
            }
        }
        .task { await load() }
    }

    func add() async {
        let text = newItem.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        newItem = ""
        _ = try? await API.shared.shoppingAdd(text)
        await load()
    }

    func load() async {
        do {
            items = try await API.shared.shoppingList()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
