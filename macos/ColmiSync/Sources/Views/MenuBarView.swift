import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var bleManager: BLEManager
    @State private var showingScanner = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "circle.hexagongrid.fill")
                    .foregroundColor(.blue)
                Text("ColmiSync")
                    .font(.headline)
                Spacer()
            }
            
            Divider()
            
            // Connection Status
            if let ring = bleManager.connectedRing {
                connectedView(ring: ring)
            } else if bleManager.isScanning {
                scanningView
            } else {
                disconnectedView
            }
            
            Divider()
            
            // Actions
            HStack {
                if bleManager.isConnected {
                    Button("Sync") {
                        Task {
                            await bleManager.syncData()
                        }
                    }
                    .disabled(bleManager.isSyncing)
                    
                    Button("Full Sync") {
                        Task {
                            await bleManager.syncHistory(days: 7)
                        }
                    }
                    .disabled(bleManager.isSyncing)
                    
                } else {
                    Button(bleManager.isScanning ? "Stop Scan" : "Scan") {
                        if bleManager.isScanning {
                            bleManager.stopScanning()
                        } else {
                            bleManager.startScanning()
                        }
                    }
                }
                
                Spacer()
                
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(width: 280)
    }
    
    @ViewBuilder
    private func connectedView(ring: DiscoveredRing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text(ring.name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let battery = bleManager.batteryLevel {
                    Label("\(battery)%", systemImage: batteryIcon(level: battery))
                        .font(.caption)
                }
            }
            
            if let hr = bleManager.lastHeartRate {
                MetricRow(icon: "heart.fill", label: "Heart Rate", value: "\(hr) BPM", color: .red)
            }
            
            if let spo2 = bleManager.lastSpO2 {
                MetricRow(icon: "lungs.fill", label: "SpO2", value: "\(spo2)%", color: .blue)
            }
            
            if let steps = bleManager.todaySteps {
                MetricRow(icon: "figure.walk", label: "Steps", value: formatNumber(steps), color: .orange)
            }
            
            if let calories = bleManager.todayCalories {
                MetricRow(icon: "flame.fill", label: "Calories", value: "\(calories) cal", color: .pink)
            }
            
            // Continuous Monitoring Settings
            if let settings = bleManager.hrLogSettings {
                Divider()
                    .padding(.vertical, 4)
                
                HStack {
                    Image(systemName: settings.enabled ? "waveform.path.ecg" : "waveform.path.ecg.rectangle")
                        .foregroundColor(settings.enabled ? .green : .gray)
                        .frame(width: 20)
                    Text("Continuous HR")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    
                    if settings.enabled {
                        Menu {
                            Button("Every 5 min") {
                                Task { try? await bleManager.enableContinuousMonitoring(intervalMinutes: 5) }
                            }
                            Button("Every 10 min") {
                                Task { try? await bleManager.enableContinuousMonitoring(intervalMinutes: 10) }
                            }
                            Button("Every 15 min") {
                                Task { try? await bleManager.enableContinuousMonitoring(intervalMinutes: 15) }
                            }
                            Button("Every 30 min") {
                                Task { try? await bleManager.enableContinuousMonitoring(intervalMinutes: 30) }
                            }
                            Button("Every 60 min") {
                                Task { try? await bleManager.enableContinuousMonitoring(intervalMinutes: 60) }
                            }
                            Divider()
                            Button("Disable") {
                                Task { try? await bleManager.disableContinuousMonitoring() }
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Text("\(settings.intervalMinutes)m")
                                    .font(.caption.weight(.medium))
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                            }
                            .foregroundColor(.green)
                        }
                        .menuStyle(.borderlessButton)
                    } else {
                        Button("Enable") {
                            Task { try? await bleManager.enableContinuousMonitoring(intervalMinutes: 5) }
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)
                    }
                }
            }
            
            if bleManager.isSyncing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Syncing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var scanningView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Scanning for rings...")
                    .font(.subheadline)
            }
            
            if !bleManager.discoveredRings.isEmpty {
                ForEach(bleManager.discoveredRings) { ring in
                    Button {
                        Task {
                            try? await bleManager.connect(to: ring)
                        }
                    } label: {
                        HStack {
                            Text(ring.name)
                            Spacer()
                            Text("RSSI: \(ring.rssi)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var disconnectedView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(.gray)
                    .frame(width: 8, height: 8)
                Text("No ring connected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Text("Click Scan to find your ring")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func batteryIcon(level: Int) -> String {
        switch level {
        case 0..<25: return "battery.25"
        case 25..<50: return "battery.50"
        case 50..<75: return "battery.75"
        default: return "battery.100"
        }
    }
    
    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

struct MetricRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(BLEManager())
}
