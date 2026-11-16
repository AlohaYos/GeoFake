import CoreLocation
import MapKit
import SwiftUI

struct ContentView: View {
    @State private var model = SensorModel()
    @State private var camera: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)

    var body: some View {
        VStack(spacing: 0) {
            map
            panel
        }
        .task { model.start() }
    }

    // MARK: Map: follows you, and shows the three fences

    private var map: some View {
        Map(position: $camera) {
            UserAnnotation()
            if let center = model.fenceCenter {
                ForEach(SensorModel.fences) { fence in
                    let inside = model.insideFences.contains(fence.id)
                    MapCircle(center: center, radius: fence.radius)
                        .foregroundStyle((inside ? Color.green : Color.orange).opacity(0.12))
                        .stroke(inside ? .green : .orange, lineWidth: 2)
                }
            }
        }
        .mapControls { MapUserLocationButton() }
        .overlay(alignment: .topLeading) { compass.padding() }
        .overlay(alignment: .bottomTrailing) {
            Button("Move fences here", systemImage: "mappin.and.ellipse") {
                if let c = model.location?.coordinate { Task { await model.setFenceCenter(c) } }
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    // MARK: Heading arrow

    private var compass: some View {
        let degrees = model.heading
        return VStack(spacing: 2) {
            Image(systemName: "location.north.line.fill")
                .font(.system(size: 34))
                .foregroundStyle(degrees == nil ? Color.secondary : Color.red)
                .rotationEffect(.degrees(degrees ?? 0))
                .animation(.easeOut(duration: 0.2), value: degrees)
            Text(degrees.map { String(format: "%.0f°", $0) } ?? "No heading")
                .font(.caption.monospacedDigit())
        }
        .frame(width: 84, height: 84)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
    }

    // MARK: Motion and the event log

    private var panel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: SensorModel.symbol(model.activity)).font(.title2).frame(width: 32)
                Text(SensorModel.name(model.activity)).font(.headline)
                Spacer()
                Text(model.insideFences.isEmpty ? "Outside all fences"
                     : "Inside: " + SensorModel.fences.map(\.id).filter(model.insideFences.contains).joined(separator: ", "))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            List(model.log) { line in
                HStack {
                    Image(systemName: line.symbol).frame(width: 24).foregroundStyle(.tint)
                    Text(line.text)
                    Spacer()
                    Text(line.date, format: .dateTime.hour().minute().second())
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            .listStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .frame(height: 300)
        .background(.background)
    }
}
