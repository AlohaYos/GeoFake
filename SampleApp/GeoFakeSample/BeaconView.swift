import CoreLocation
import SwiftUI

struct BeaconView: View {
    @State private var model = BeaconModel()

    var body: some View {
        NavigationStack {
            List {
                Section("Beacon UUID") {
                    TextField("UUID", text: $model.uuidText)
                        .font(.footnote.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button(model.running ? "Stop" : "Start Ranging") {
                        model.running ? model.stop() : model.start()
                    }
                }
                Section {
                    if model.beacons.isEmpty {
                        Text(model.running ? "No beacons in range" : "Not ranging").foregroundStyle(.secondary)
                    }
                    ForEach(model.beacons) { b in
                        HStack {
                            Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(color(b.proximity))
                            VStack(alignment: .leading) {
                                Text("Major \(b.major) · Minor \(b.minor)").font(.headline)
                                Text(String(format: "%.1f m · %d dBm", b.accuracy, b.rssi))
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(BeaconModel.name(b.proximity)).font(.subheadline.bold()).foregroundStyle(color(b.proximity))
                        }
                    }
                } header: {
                    HStack {
                        Text("Ranging")
                        Spacer()
                        switch model.inside {
                        case true?: Label("Inside region", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case false?: Label("Outside region", systemImage: "xmark.circle").foregroundStyle(.orange)
                        case nil: EmptyView()
                        }
                    }
                }
                Section("Events") {
                    ForEach(model.log) { line in
                        HStack {
                            Image(systemName: line.symbol).frame(width: 24).foregroundStyle(.tint)
                            Text(line.text)
                            Spacer()
                            Text(line.date, format: .dateTime.hour().minute().second())
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            }
            .navigationTitle("Beacons")
        }
        .task {
            #if DEBUG
            // For automated checks: start ranging right away
            if UserDefaults.standard.bool(forKey: "SampleStartBeacons") { model.start() }
            #endif
        }
    }

    private func color(_ p: CLProximity) -> Color {
        switch p {
        case .immediate: .red
        case .near: .orange
        case .far: .blue
        default: .gray
        }
    }
}
