import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var bleManager: BLEManager
    @AppStorage("autoSync") private var autoSync = true
    @AppStorage("syncInterval") private var syncInterval = 30
    @AppStorage("savedRingAddress") private var savedRingAddress = ""
    
    @State private var hrInterval: Int = 10
    @State private var hrEnabled: Bool = true
    @State private var stressEnabled: Bool = true
    @State private var hrvEnabled: Bool = true
    @State private var isApplying: Bool = false
    
    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            monitoringSettings
                .tabItem {
                    Label("Monitoring", systemImage: "waveform.path.ecg")
                }
            
            connectionSettings
                .tabItem {
                    Label("Connection", systemImage: "antenna.radiowaves.left.and.right")
                }
            
            dataSettings
                .tabItem {
                    Label("Data", systemImage: "externaldrive")
                }
        }
        .frame(width: 450, height: 350)
    }
    
    private var monitoringSettings: some View {
        Form {
            Section("Continuous Heart Rate") {
                Toggle("Enable HR Monitoring", isOn: $hrEnabled)
                
                if hrEnabled {
                    Picker("Measurement Interval", selection: $hrInterval) {
                        Text("Every 5 min (more data, less battery)").tag(5)
                        Text("Every 10 min (recommended)").tag(10)
                        Text("Every 15 min").tag(15)
                        Text("Every 30 min").tag(30)
                        Text("Every 60 min (less data, more battery)").tag(60)
                    }
                }
            }
            
            Section("Other Monitoring") {
                Toggle("Stress Monitoring", isOn: $stressEnabled)
                Toggle("HRV Monitoring", isOn: $hrvEnabled)
            }
            
            Section {
                HStack {
                    Button("Apply to Ring") {
                        applyMonitoringSettings()
                    }
                    .disabled(!bleManager.isConnected || isApplying)
                    
                    if isApplying {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
                
                if !bleManager.isConnected {
                    Text("Connect to ring to apply settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            // Load current settings from ring if connected
            if let settings = bleManager.hrLogSettings {
                hrEnabled = settings.enabled
                hrInterval = settings.intervalMinutes
            }
        }
    }
    
    private func applyMonitoringSettings() {
        isApplying = true
        Task {
            do {
                if hrEnabled {
                    try await bleManager.enableContinuousMonitoring(intervalMinutes: hrInterval)
                } else {
                    try await bleManager.disableContinuousMonitoring()
                }
                // TODO: Apply stress/HRV settings when API available
            } catch {
                print("Failed to apply settings: \(error)")
            }
            isApplying = false
        }
    }
    
    private var generalSettings: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: .constant(false))
                    .disabled(true) // TODO: Implement
                
                Toggle("Show in menu bar", isOn: .constant(true))
                    .disabled(true)
            }
            
            Section("Notifications") {
                Toggle("Low battery alert", isOn: .constant(true))
                    .disabled(true) // TODO: Implement
                
                Toggle("Sync complete", isOn: .constant(false))
                    .disabled(true)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    private var connectionSettings: some View {
        Form {
            Section("Auto-Connect") {
                Toggle("Auto-connect on launch", isOn: $autoSync)
                
                if !savedRingAddress.isEmpty {
                    LabeledContent("Saved Ring") {
                        Text(savedRingAddress)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Forget Ring", role: .destructive) {
                        savedRingAddress = ""
                    }
                }
            }
            
            Section("Sync") {
                Picker("Sync interval", selection: $syncInterval) {
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("Manual only").tag(0)
                }
            }
            
            Section("Current Connection") {
                if let ring = bleManager.connectedRing {
                    LabeledContent("Ring") {
                        Text(ring.name)
                    }
                    LabeledContent("Signal") {
                        Text("\(ring.rssi) dBm")
                    }
                    if let battery = bleManager.batteryLevel {
                        LabeledContent("Battery") {
                            Text("\(battery)%")
                        }
                    }
                    
                    Button("Disconnect") {
                        bleManager.disconnect()
                    }
                } else {
                    Text("No ring connected")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    private var dataSettings: some View {
        Form {
            Section("Storage") {
                LabeledContent("Data Location") {
                    Text("~/clawd/health/")
                        .foregroundColor(.secondary)
                }
                
                Button("Open in Finder") {
                    let url = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("clawd/health")
                    NSWorkspace.shared.open(url)
                }
            }
            
            Section("Export") {
                Button("Export All Data (JSON)") {
                    // TODO: Implement
                }
                .disabled(true)
                
                Button("Export to Apple Health") {
                    // TODO: Implement
                }
                .disabled(true)
            }
            
            Section("Danger Zone") {
                Button("Clear All Data", role: .destructive) {
                    // TODO: Implement with confirmation
                }
                .disabled(true)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView()
        .environmentObject(BLEManager())
}
