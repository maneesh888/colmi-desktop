import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var bleManager: BLEManager
    @AppStorage("autoSync") private var autoSync = true
    @AppStorage("syncInterval") private var syncInterval = 30
    @AppStorage("savedRingAddress") private var savedRingAddress = ""
    
    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gear")
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
        .frame(width: 450, height: 300)
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
