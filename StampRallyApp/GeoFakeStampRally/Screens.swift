import MapKit
import SwiftUI

/// Stamp ink
let inkColor = Color(red: 0.84, green: 0.16, blue: 0.22)

// MARK: Stamp book

struct StampBookScreen: View {
    @Environment(RallyModel.self) private var model
    @State private var confirmingReset = false

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(model.spots) { spot in
                            StampCell(spot: spot, stamp: model.stamp(for: spot))
                                .contextMenu {
                                    Button("Delete Spot", systemImage: "trash", role: .destructive) { model.delete(spot) }
                                }
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Stamp Rally")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset") { confirmingReset = true }
                        .disabled(model.stamps.isEmpty)
                }
            }
            .confirmationDialog("Reset all stamps?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset Stamps", role: .destructive) { model.resetStamps() }
            } message: {
                Text("Your spots stay. Only the stamps are cleared.")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(progressText(collected: model.stamps.count, total: model.spots.count))
                .font(.title2.weight(.heavy)).fontDesign(.rounded)
            ProgressView(value: Double(model.stamps.count), total: Double(max(model.spots.count, 1)))
                .tint(inkColor)
            HStack(spacing: 8) {
                MovementChip(movement: model.movement)
                Text("Walk into a spot to collect its stamp. Arriving by car doesn't count.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct StampCell: View {
    let spot: Spot
    let stamp: Stamp?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let stamp {
                    StampMark(name: spot.name, symbol: spot.symbol, date: stamp.date, size: 112)
                } else {
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        .foregroundStyle(.tertiary)
                    Image(systemName: spot.symbol)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.quaternary)
                }
            }
            .frame(width: 112, height: 112)

            Text(spot.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            if let stamp {
                HStack(spacing: 4) {
                    Image(systemName: stamp.movement.symbol)
                    Text(stamp.date, format: .dateTime.hour().minute())
                }
                .font(.caption).foregroundStyle(inkColor)
            } else {
                Text("Not yet").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }
}

/// A round rubber stamp: double ring, the spot's symbol, its name and the date
struct StampMark: View {
    let name: String
    let symbol: String
    let date: Date?
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            Circle().strokeBorder(inkColor, lineWidth: size * 0.045)
            Circle().strokeBorder(inkColor, lineWidth: size * 0.015).padding(size * 0.085)
            VStack(spacing: size * 0.02) {
                Image(systemName: symbol).font(.system(size: size * 0.27, weight: .bold))
                Text(name.uppercased())
                    .font(.system(size: size * 0.085, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.6)
                if let date {
                    Text(date, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
                        .font(.system(size: size * 0.07, weight: .semibold, design: .monospaced))
                }
            }
            .padding(size * 0.17)
        }
        .foregroundStyle(inkColor)
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-12))
        .opacity(0.92)
    }
}

struct MovementChip: View {
    let movement: Movement?

    var body: some View {
        Label(movement?.title ?? "Motion unknown", systemImage: movement?.symbol ?? "questionmark")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.thinMaterial, in: .capsule)
            .fixedSize()
    }
}

// MARK: Arrival: stamp animation or "walk in" banner

struct ArrivalOverlay: View {
    @Environment(RallyModel.self) private var model

    var body: some View {
        ZStack {
            if let event = model.event {
                if event.decision == .stamp {
                    StampCelebration(event: event).id(event.id)
                } else if let text = refusalText(event.decision) {
                    RefusalBanner(event: event, text: text).id(event.id)
                }
            }
        }
        .sensoryFeedback(trigger: model.event) { _, new in
            guard let new else { return nil }
            return new.decision == .stamp ? .success : .warning
        }
    }
}

struct StampCelebration: View {
    @Environment(RallyModel.self) private var model
    let event: RallyEvent
    @State private var landed = false

    var body: some View {
        ZStack {
            Color.black.opacity(landed ? 0.35 : 0).ignoresSafeArea()
            VStack(spacing: 24) {
                ZStack {
                    // Ink splash ring that spreads as the stamp lands
                    Circle()
                        .stroke(inkColor, lineWidth: 3)
                        .frame(width: 230, height: 230)
                        .scaleEffect(landed ? 1.5 : 0.9)
                        .opacity(landed ? 0 : 0.6)
                    StampMark(name: event.spot.name, symbol: event.spot.symbol, date: .now, size: 230)
                        .padding(18)
                        .background(Color(.systemBackground).opacity(0.95), in: .circle)
                        .scaleEffect(landed ? 1 : 2.6)
                        .rotationEffect(.degrees(landed ? 0 : -25))
                        .opacity(landed ? 1 : 0)
                }
                VStack(spacing: 6) {
                    Text("Stamped!").font(.largeTitle.weight(.heavy)).fontDesign(.rounded)
                    Label("Arrived \(event.movement?.title.lowercased() ?? "")", systemImage: event.movement?.symbol ?? "figure.walk")
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .opacity(landed ? 1 : 0)
            }
        }
        .contentShape(.rect)
        .onTapGesture { withAnimation(.easeOut(duration: 0.25)) { model.dismiss(event) } }
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { landed = true }
        }
        .task {
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(.easeOut(duration: 0.4)) { model.dismiss(event) }
        }
        .transition(.opacity)
    }
}

struct RefusalBanner: View {
    @Environment(RallyModel.self) private var model
    let event: RallyEvent
    let text: String
    @State private var shown = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.movement?.symbol ?? "questionmark")
                .font(.title2).frame(width: 40, height: 40)
                .background(Color.orange.opacity(0.2), in: .circle)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.spot.name).font(.subheadline.weight(.semibold))
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
        .shadow(radius: 8, y: 3)
        .padding(.horizontal)
        .offset(y: shown ? 0 : -160)
        .frame(maxHeight: .infinity, alignment: .top)
        .onTapGesture { model.dismiss(event) }
        .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { shown = true } }
        .task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.easeIn(duration: 0.3)) { shown = false }
            try? await Task.sleep(for: .seconds(0.3))
            model.dismiss(event)
        }
    }
}

// MARK: Map

struct MapScreen: View {
    @Environment(RallyModel.self) private var model
    @State private var camera: MapCameraPosition = .automatic
    @State private var adding: Spot?

    var body: some View {
        VStack(spacing: 0) {
            MapReader { proxy in
                Map(position: $camera) {
                    UserAnnotation()
                    ForEach(model.spots) { spot in
                        let done = model.stamp(for: spot) != nil
                        let color: Color = done ? inkColor : .orange
                        MapCircle(center: spot.coordinate, radius: spot.radius)
                            .foregroundStyle(color.opacity(0.15))
                            .stroke(color, lineWidth: 2)
                        Annotation(spot.name, coordinate: spot.coordinate, anchor: .center) {
                            Image(systemName: done ? "checkmark.seal.fill" : spot.symbol)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(color, in: .circle)
                        }
                    }
                }
                .mapControls { MapUserLocationButton() }
                // Long press, then the finger's position, adds a spot there
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.6)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                        .onEnded { value in
                            guard case .second(true, let drag?) = value,
                                  let c = proxy.convert(drag.location, from: .local) else { return }
                            adding = Spot(name: "", latitude: c.latitude, longitude: c.longitude, radius: defaultRadius, symbol: symbolChoices[0])
                        }
                )
                .overlay(alignment: .top) {
                    Text("Long-press the map to add a spot")
                        .font(.caption).padding(6)
                        .background(.regularMaterial, in: .capsule)
                        .padding(.top, 8)
                }
            }
            panel
        }
        .sheet(item: $adding) { SpotEditor(spot: $0) }
    }

    private var panel: some View {
        let names = model.spots.filter { model.insideIDs.contains($0.id) }.map(\.name)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                MovementChip(movement: model.movement)
                Spacer()
                Label("\(model.stamps.count) / \(model.spots.count)", systemImage: "seal.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(inkColor)
            }
            Text(names.isEmpty ? "Not inside any spot" : "Inside: " + names.joined(separator: ", "))
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background)
    }
}

// MARK: Add sheet

struct SpotEditor: View {
    @Environment(RallyModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var spot: Spot

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $spot.name)
                Picker("Radius", selection: $spot.radius) {
                    ForEach(radiusChoices, id: \.self) { Text("\(Int($0)) m").tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Symbol", selection: $spot.symbol) {
                    ForEach(symbolChoices, id: \.self) { Image(systemName: $0).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .navigationTitle("New Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        spot.name = spot.name.trimmingCharacters(in: .whitespaces)
                        model.add(spot)
                        dismiss()
                    }
                    .disabled(spot.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
