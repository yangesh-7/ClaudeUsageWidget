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
        ZStack {
            // MARK: - Dark Background Gradient
            LinearGradient(
                colors: [Color.black, Color(white: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .overlay(
                Circle()
                    .fill(Color.blue.opacity(0.05))
                    .frame(width: 400, height: 400)
                    .blur(radius: 80)
                    .offset(x: -150, y: -150)
            )
            .overlay(
                Circle()
                    .fill(Color.purple.opacity(0.05))
                    .frame(width: 300, height: 300)
                    .blur(radius: 60)
                    .offset(x: 200, y: 150)
            )
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // MARK: - Header
                    HStack(spacing: 16) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: .purple.opacity(0.3), radius: 5, x: 0, y: 3)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI Usage Tracker")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("Codex + Antigravity")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 8)
                    
                    // MARK: - Info Section
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("About", systemImage: "info.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.blue)
                            
                            Text("This widget seamlessly reads your local AI session data in the background. No configuration needed.")
                                .font(.subheadline)
                                .foregroundColor(.primary.opacity(0.8))
                        }
                    }
                    
                    // MARK: - Status Cards
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Data Source Status", systemImage: "checkmark.shield.fill")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            
                            VStack(spacing: 12) {
                                statusRow(
                                    name: "Codex",
                                    icon: "CodexLogo",
                                    detected: codexHistoryExists
                                )
                                
                                Rectangle()
                                    .fill(Color.primary.opacity(0.1))
                                    .frame(height: 1)
                                
                                statusRow(
                                    name: "Antigravity",
                                    icon: "AntigravityLogo",
                                    detected: antigravityHistoryExists
                                )
                            }
                        }
                    }
                    
                    // MARK: - Paths Monitored
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Paths Monitored", systemImage: "folder.badge.gearshape.fill")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                pathRow(label: "Codex history", path: codexHistoryPath)
                                Rectangle()
                                    .fill(Color.primary.opacity(0.1))
                                    .frame(height: 1)
                                pathRow(label: "Antigravity history", path: antigravityHistoryPath)
                            }
                        }
                    }
                    
                    // MARK: - Refresh Button
                    Button(action: {
                        withAnimation {
                            WidgetCenter.shared.reloadTimelines(ofKind: "AIUsageWidget")
                            checkDataSources()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Refresh Widgets")
                        }
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                .padding(32)
            }
        }
        .frame(minWidth: 500, minHeight: 480)
        .preferredColorScheme(.dark)
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
                .frame(width: 24, height: 24)
                .frame(width: 32)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            
            Text(name)
                .font(.body.weight(.semibold))
            
            Spacer()
            
            HStack(spacing: 6) {
                Image(systemName: detected ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(detected ? .green : .red)
                    .font(.title3)
                
                Text(detected ? "Detected" : "Not Found")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(detected ? .green : .red)
            }
        }
    }
    
    private func pathRow(label: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline.weight(.semibold))
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

// MARK: - Glassmorphism Card
struct GlassCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(.regularMaterial)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 15, x: 0, y: 5)
    }
}

#Preview {
    ContentView()
}
