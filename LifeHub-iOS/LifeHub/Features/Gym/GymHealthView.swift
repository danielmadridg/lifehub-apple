import SwiftUI
import Charts
import PhotosUI

/// Salud: peso corporal, perímetros, fotos de progreso y datos de Apple Health
/// que llegan al backend (pasos, sueño, pulso).
struct GymHealthView: View {
    @State private var bodyweight: [BodyWeightEntry] = []
    @State private var measures: Measures = [:]
    @State private var photos: [ProgressPhotoItem] = []
    @State private var healthDays: [HealthDay] = []
    @State private var loaded = false

    @State private var newWeight = ""
    @State private var photoPick: PhotosPickerItem?

    var body: some View {
        Screen(title: "Salud", refresh: { await load() }) {
            if !loaded {
                SkeletonList()
            } else {
                // ── Peso corporal ──
                SectionHeader(title: "Peso corporal")
                HStack {
                    TextField("Peso (kg)", text: $newWeight)
                        .keyboardType(.decimalPad)
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.ink)
                    Button {
                        Task { await addWeight() }
                    } label: {
                        Text("Apuntar")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.black)
                    }
                    .disabled(Double(newWeight.replacingOccurrences(of: ",", with: ".")) == nil)
                }

                if bodyweight.count > 1 {
                    Chart(bodyweight.reversed(), id: \.id) { entry in
                        LineMark(
                            x: .value("Fecha", Fmt.date(entry.at) ?? .now),
                            y: .value("Peso", entry.weight)
                        )
                        .foregroundStyle(Theme.accent)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 160)
                    .card()
                }
                if let last = bodyweight.first {
                    Text("Último: \(last.weight.clean) kg · \(Fmt.short(last.at))")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }

                // ── Perímetros ──
                SectionHeader(title: "Perímetros")
                ForEach(["brazo", "pecho", "cintura", "pierna"], id: \.self) { site in
                    MeasureRow(site: site, entries: measures[site] ?? []) {
                        await load()
                    }
                }

                // ── Fotos de progreso ──
                SectionHeader(title: "Fotos de progreso")
                PhotosPicker(selection: $photoPick, matching: .images) {
                    Label("Subir foto", systemImage: "camera.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Theme.accent)
                }
                .onChange(of: photoPick) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            _ = try? await API.shared.gymUploadPhoto(data)
                            await load()
                        }
                        photoPick = nil
                    }
                }

                if !photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(photos) { photo in
                                VStack(spacing: 4) {
                                    AsyncImage(url: API.shared.imageURL(photo.url)) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Theme.surface2
                                    }
                                    .frame(width: 110, height: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    Text(Fmt.short(photo.at))
                                        .font(.caption2)
                                        .foregroundStyle(Theme.muted)
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        Task {
                                            _ = try? await API.shared.gymDeletePhoto(photo.id)
                                            await load()
                                        }
                                    } label: {
                                        Label("Borrar", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Apple Health (vía Atajo → backend) ──
                if !healthDays.isEmpty {
                    SectionHeader(title: "Salud diaria")
                    ForEach(healthDays.prefix(7), id: \.day) { d in
                        HStack {
                            Text(Fmt.short(d.day))
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text([
                                d.steps.map { "\($0) pasos" },
                                d.sleep_hours.map { "\($0.clean) h sueño" },
                                d.resting_hr.map { "\($0) ppm" },
                            ].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        .card(padding: 12)
                    }
                }
            }
        }
        .task { await load() }
    }

    func addWeight() async {
        guard let w = Double(newWeight.replacingOccurrences(of: ",", with: ".")) else { return }
        newWeight = ""
        _ = try? await API.shared.gymAddBodyweight(w)
        Haptics.success()
        await load()
    }

    func load() async {
        async let bw = try? API.shared.gymBodyweight()
        async let m = try? API.shared.gymMeasures()
        async let p = try? API.shared.gymPhotos()
        async let h = try? API.shared.health()
        bodyweight = await bw ?? []
        measures = await m ?? [:]
        photos = await p ?? []
        healthDays = await h ?? []
        loaded = true
    }
}

struct MeasureRow: View {
    let site: String
    let entries: [MeasureEntry]
    let onChange: () async -> Void

    @State private var value = ""

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(site.capitalized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if let last = entries.first {
                    Text("\(last.value.clean) cm · \(Fmt.short(last.at))")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                } else {
                    Text("Sin datos")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            TextField("cm", text: $value)
                .keyboardType(.decimalPad)
                .frame(width: 60)
                .padding(8)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Theme.ink)
            Button {
                Task {
                    guard let v = Double(value.replacingOccurrences(of: ",", with: ".")) else { return }
                    value = ""
                    _ = try? await API.shared.gymAddMeasure(site: site, value: v)
                    await onChange()
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Theme.accent)
            }
            .disabled(Double(value.replacingOccurrences(of: ",", with: ".")) == nil)
        }
        .card(padding: 13)
    }
}
