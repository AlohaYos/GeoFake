import MapKit
import SwiftUI

// MARK: Map

struct MapScreen: View {
    @Environment(ArrivalModel.self) private var model
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var editing: Spot?

    var body: some View {
        VStack(spacing: 0) {
            MapReader { proxy in
                Map(position: $camera) {
                    UserAnnotation()
                    ForEach(model.spots) { spot in
                        let inside = model.insideIDs.contains(spot.id)
                        MapCircle(center: spot.coordinate, radius: spot.radius)
                            .foregroundStyle((inside ? Color.green : Color.orange).opacity(0.15))
                            .stroke(inside ? .green : .orange, lineWidth: 2)
                        Annotation(spot.name, coordinate: spot.coordinate, anchor: .center) {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(inside ? .green : .orange)
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
                            editing = Spot(name: "", latitude: c.latitude, longitude: c.longitude, radius: defaultRadius)
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
        .sheet(item: $editing) { SpotEditor(spot: $0) }
    }

    private var panel: some View {
        let names = model.spots.filter { model.insideIDs.contains($0.id) }.map(\.name)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: model.movement?.symbol ?? "questionmark").font(.title2).frame(width: 32)
                Text(model.movement?.title ?? "Motion unknown").font(.headline)
            }
            Text(names.isEmpty ? "Not inside any spot" : "Inside: " + names.joined(separator: ", "))
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background)
    }
}

// MARK: Spot list

struct SpotsScreen: View {
    @Environment(ArrivalModel.self) private var model
    @State private var editing: Spot?

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.spots) { spot in
                    Button { editing = spot } label: {
                        HStack {
                            Image(systemName: model.insideIDs.contains(spot.id) ? "mappin.circle.fill" : "mappin.circle")
                                .foregroundStyle(model.insideIDs.contains(spot.id) ? .green : .orange)
                            Text(spot.name)
                            Spacer()
                            Text("\(Int(spot.radius)) m").foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { offsets in offsets.map { model.spots[$0] }.forEach(model.delete) }
            }
            .overlay {
                if model.spots.isEmpty {
                    ContentUnavailableView("No spots yet", systemImage: "mappin.slash", description: Text("Long-press the map to add one."))
                }
            }
            .navigationTitle("Spots")
        }
        .sheet(item: $editing) { SpotEditor(spot: $0) }
    }
}

// MARK: Add / edit sheet

struct SpotEditor: View {
    @Environment(ArrivalModel.self) private var model
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
            }
            .navigationTitle("Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        spot.name = spot.name.trimmingCharacters(in: .whitespaces)
                        model.save(spot)
                        dismiss()
                    }
                    .disabled(spot.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: History

struct HistoryScreen: View {
    @Environment(ArrivalModel.self) private var model

    var body: some View {
        NavigationStack {
            List(model.history) { entry in
                HStack {
                    Image(systemName: entry.entered ? "arrow.down.right.circle" : "arrow.up.left.circle")
                        .foregroundStyle(entry.entered ? .green : .orange)
                    VStack(alignment: .leading) {
                        Text("\(entry.entered ? "Entered" : "Left") \(entry.spot)")
                        Label(entry.movement?.title ?? "Motion unknown", systemImage: entry.movement?.symbol ?? "questionmark")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(entry.date, format: .dateTime.hour().minute().second())
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .overlay {
                if model.history.isEmpty {
                    ContentUnavailableView("No history yet", systemImage: "clock", description: Text("Entering or leaving a spot shows up here."))
                }
            }
            .navigationTitle("History")
        }
    }
}
