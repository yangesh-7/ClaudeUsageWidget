import SwiftUI
import WidgetKit
import Darwin

struct ContentView: View {
    @State private var codexHistoryExists: Bool = false
    @State private var antigravityHistoryExists: Bool = false
    
    private var homeDirectory: String {
        if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
            return String(cString: home)
        }
        return NSHomeDirectory()
    }
    
    private var codexHistoryPath: String {
        "\(homeDirectory)/.codex/history.jsonl"
    }
    
    private var antigravityHistoryPath: String {
        "\(homeDirectory)/.gemini/antigravity-cli/history.jsonl"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: - Header
                HStack(spacing: 12) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.linearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Usage Tracker")
                            .font(.title.bold())
                        Text("Codex + Antigravity")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.bottom, 4)
                
                // MARK: - Info Section
                GroupBox {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title3)
                        
                        Text("This widget automatically reads your local Codex and Antigravity session data. No configuration needed!")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("About", systemImage: "questionmark.circle")
                        .font(.headline)
                }
                
                // MARK: - Status Cards
                GroupBox {
                    VStack(spacing: 12) {
                        statusRow(
                            name: "Codex",
                            icon: "CodexLogo",
                            detected: codexHistoryExists
                        )
                        
                        Divider()
                        
                        statusRow(
                            name: "Antigravity",
                            icon: "AntigravityLogo",
                            detected: antigravityHistoryExists
                        )
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("Data Source Status", systemImage: "checkmark.shield")
                        .font(.headline)
                }
                
                // MARK: - Paths Monitored
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        pathRow(label: "Codex history", path: codexHistoryPath)
                        Divider()
                        pathRow(label: "Antigravity history", path: antigravityHistoryPath)
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("Paths Monitored", systemImage: "folder.badge.gearshape")
                        .font(.headline)
                }
                
                // MARK: - Refresh Button
                Button(action: {
                    WidgetCenter.shared.reloadTimelines(ofKind: "AIUsageWidget")
                    checkDataSources()
                }) {
                    Label("Refresh Widget", systemImage: "arrow.clockwise")
                        .font(.body.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .padding(24)
        }
        .frame(minWidth: 500, minHeight: 350)
        .onAppear {
            checkDataSources()
        }
    }
    
    // MARK: - Subviews
    
    private func statusRow(name: String, icon: String, detected: Bool) -> some View {
        HStack {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .frame(width: 28)
            
            Text(name)
                .font(.body.weight(.medium))
            
            Spacer()
            
            HStack(spacing: 6) {
                Image(systemName: detected ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(detected ? .green : .red)
                    .font(.title3)
                
                Text(detected ? "Detected" : "Not Found")
                    .font(.callout)
                    .foregroundColor(detected ? .green : .red)
            }
        }
    }
    
    private func pathRow(label: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundColor(.primary)
            
            Text(path)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
    }
    
    // MARK: - Helpers
    
    private func checkDataSources() {
        codexHistoryExists = FileManager.default.fileExists(atPath: codexHistoryPath)
        antigravityHistoryExists = FileManager.default.fileExists(atPath: antigravityHistoryPath)
    }
}

#Preview {
    ContentView()
}
