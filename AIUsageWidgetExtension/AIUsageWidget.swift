import WidgetKit
import SwiftUI
import Darwin

// MARK: - Models

struct AGYStats {
    let model: String
    let sessionsToday: Int
    let sessionsWeek: Int
    let promptsToday: Int
    let promptsWeek: Int
    let slashCommandsToday: Int
    let topWorkspaceToday: String
}

struct CodexStats {
    let sessionsToday: Int
    let sessionsWeek: Int
    let primaryUsedPercent: Double?
    let primaryResetAt: Date?
    let primaryLimit: String?
    let secondaryUsedPercent: Double?
    let secondaryResetAt: Date?
    let secondaryLimit: String?
}

struct AIUsageEntry: TimelineEntry {
    let date: Date
    let stats: AGYStats // for backwards compatibility
    let agyStats: AGYStats
    let codexStats: CodexStats
    let error: String?

    static var placeholder: AIUsageEntry {
        let agy = AGYStats(
            model: "gemini-1.5-pro",
            sessionsToday: 5,
            sessionsWeek: 23,
            promptsToday: 42,
            promptsWeek: 156,
            slashCommandsToday: 3,
            topWorkspaceToday: "AntigravityApp"
        )
        let codex = CodexStats(
            sessionsToday: 2,
            sessionsWeek: 10,
            primaryUsedPercent: 0.45,
            primaryResetAt: Date().addingTimeInterval(3600 * 2.5),
            primaryLimit: "5h limit",
            secondaryUsedPercent: 0.1,
            secondaryResetAt: Date().addingTimeInterval(3600 * 4),
            secondaryLimit: "24h limit"
        )
        return AIUsageEntry(date: Date(), stats: agy, agyStats: agy, codexStats: codex, error: nil)
    }
}

// MARK: - API & Auth

struct CodexAuth: Codable {
    struct Tokens: Codable {
        let access_token: String
        let account_id: String
    }
    let tokens: Tokens
}

struct CodexUsageResponse: Codable {
    struct RateLimit: Codable {
        struct Window: Codable {
            let used_percent: Int
            let reset_at: Int
            let limit_window_seconds: Int?
        }
        let primary_window: Window
        let secondary_window: Window?
    }
    let rate_limit: RateLimit
}

struct CodexAPI {
    static func formatLimit(_ seconds: Int?) -> String? {
        guard let s = seconds else { return nil }
        if s == 18000 { return "5h limit" }
        if s == 604800 { return "Weekly limit" }
        if s == 2592000 { return "Monthly limit" }
        let hours = s / 3600
        return "\(hours)h limit"
    }

    static func fetchUsage(auth: CodexAuth) async throws -> (primaryUsed: Double, primaryReset: Date, primaryLimit: String?, secondaryUsed: Double?, secondaryReset: Date?, secondaryLimit: String?) {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 3.0
        request.addValue("Bearer \(auth.tokens.access_token)", forHTTPHeaderField: "Authorization")
        request.addValue(auth.tokens.account_id, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.addValue("codex_cli_rs", forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let usage = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        
        let pPercent = Double(usage.rate_limit.primary_window.used_percent) / 100.0
        let pReset = Date(timeIntervalSince1970: TimeInterval(usage.rate_limit.primary_window.reset_at))
        let pLimit = formatLimit(usage.rate_limit.primary_window.limit_window_seconds)
        
        var sPercent: Double? = nil
        var sReset: Date? = nil
        var sLimit: String? = nil
        
        if let sec = usage.rate_limit.secondary_window {
            sPercent = Double(sec.used_percent) / 100.0
            sReset = Date(timeIntervalSince1970: TimeInterval(sec.reset_at))
            sLimit = formatLimit(sec.limit_window_seconds)
        }
        
        return (pPercent, pReset, pLimit, sPercent, sReset, sLimit)
    }
}

// MARK: - Formatting helpers

func formatRemainingTime(date: Date?) -> String {
    guard let date = date else { return "Unknown" }
    let diff = date.timeIntervalSince(Date())
    if diff <= 0 { return "Reset" }
    
    let hours = Int(diff) / 3600
    let minutes = (Int(diff) % 3600) / 60
    
    if hours > 0 {
        return "Resets in: \(hours)h \(minutes)m"
    } else {
        return "Resets in: \(minutes)m"
    }
}

// MARK: - Home & Date

private enum Home {
    static var url: URL {
        if let passwd = getpwuid(getuid()) {
            return URL(fileURLWithPath: String(cString: passwd.pointee.pw_dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}

private enum DateRange {
    static var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    static var startOfWeek: Date {
        let cal = Calendar.current
        let today = Date()
        let weekday = cal.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        return cal.startOfDay(for: cal.date(byAdding: .day, value: -daysSinceMonday, to: today)!)
    }
}

// MARK: - Parser

struct AIUsageParser {
    static func parse() async -> AIUsageEntry {
        let agy = parseAGY()
        let codex = await parseCodex()
        return AIUsageEntry(date: Date(), stats: agy, agyStats: agy, codexStats: codex, error: nil)
    }

    private static func parseAGY() -> AGYStats {
        let agyBase = Home.url.appendingPathComponent(".gemini", isDirectory: true).appendingPathComponent("antigravity-cli", isDirectory: true)
        let settingsPath = agyBase.appendingPathComponent("settings.json", isDirectory: false)
        let historyPath = agyBase.appendingPathComponent("history.jsonl", isDirectory: false)

        var model = "Unknown Model"
        if let data = try? Data(contentsOf: settingsPath),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let m = obj["model"] as? String {
            model = m
        }

        var sessionsToday = Set<String>()
        var sessionsWeek = Set<String>()
        var promptsToday = 0
        var promptsWeek = 0
        var slashToday = 0
        var workspaces: [String: Int] = [:]

        let today = DateRange.startOfToday
        let week = DateRange.startOfWeek

        if let lines = readLines(at: historyPath) {
            for line in lines {
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tsNum = obj["timestamp"] as? NSNumber else { continue }

                let date = Date(timeIntervalSince1970: tsNum.doubleValue / 1000.0)
                let cid = obj["conversationId"] as? String ?? "u"
                let w = obj["workspace"] as? String ?? "None"
                let wName = (w as NSString).lastPathComponent

                if date >= week {
                    sessionsWeek.insert(cid)
                    promptsWeek += 1
                }
                if date >= today {
                    sessionsToday.insert(cid)
                    promptsToday += 1
                    if (obj["type"] as? String) == "slash_command" {
                        slashToday += 1
                    }
                    workspaces[wName, default: 0] += 1
                }
            }
        }

        let topW = workspaces.max { $0.value < $1.value }?.key ?? "None"

        return AGYStats(model: model, sessionsToday: sessionsToday.count, sessionsWeek: sessionsWeek.count, promptsToday: promptsToday, promptsWeek: promptsWeek, slashCommandsToday: slashToday, topWorkspaceToday: topW)
    }

    private static func parseCodex() async -> CodexStats {
        let codexBase = Home.url.appendingPathComponent(".codex", isDirectory: true)
        let historyPath = codexBase.appendingPathComponent("history.jsonl", isDirectory: false)
        let authPath = codexBase.appendingPathComponent("auth.json", isDirectory: false)

        var sessionsToday = Set<String>()
        var sessionsWeek = Set<String>()

        let today = DateRange.startOfToday
        let week = DateRange.startOfWeek

        if let lines = readLines(at: historyPath) {
            for line in lines {
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tsNum = obj["ts"] as? NSNumber else { continue }
                
                // Codex ts is in seconds
                let date = Date(timeIntervalSince1970: tsNum.doubleValue)
                let cid = obj["session_id"] as? String ?? "u"

                if date >= week { sessionsWeek.insert(cid) }
                if date >= today { sessionsToday.insert(cid) }
            }
        }

        var pPercent: Double?
        var pReset: Date?
        var pLimit: String?
        var sPercent: Double?
        var sReset: Date?
        var sLimit: String?

        if let authData = try? Data(contentsOf: authPath),
           let auth = try? JSONDecoder().decode(CodexAuth.self, from: authData) {

            if let result = try? await CodexAPI.fetchUsage(auth: auth) {
                pPercent = result.primaryUsed
                pReset = result.primaryReset
                pLimit = result.primaryLimit
                
                sPercent = result.secondaryUsed
                sReset = result.secondaryReset
                sLimit = result.secondaryLimit
            }
        }

        return CodexStats(
            sessionsToday: sessionsToday.count,
            sessionsWeek: sessionsWeek.count,
            primaryUsedPercent: pPercent,
            primaryResetAt: pReset,
            primaryLimit: pLimit,
            secondaryUsedPercent: sPercent,
            secondaryResetAt: sReset,
            secondaryLimit: sLimit
        )
    }

    private static func readLines(at url: URL) -> [String]? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

// MARK: - Provider

struct AIUsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> AIUsageEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (AIUsageEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task {
            let entry = await AIUsageParser.parse()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AIUsageEntry>) -> Void) {
        Task {
            let entry = await AIUsageParser.parse()
            let next = Date().addingTimeInterval(5 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

// MARK: - Colors

extension Color {
    static let agyBlue = Color(red: 0.259, green: 0.522, blue: 0.957)
    static let agyPurple = Color(red: 0.556, green: 0.266, blue: 0.898)
    static let codexGreen = Color(red: 0.1, green: 0.65, blue: 0.4)
    
    static var agyGradient: LinearGradient {
        LinearGradient(
            colors: [agyBlue, agyPurple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Reusable Views (AGY)

struct StatBox: View {
    let title: String
    let today: Int
    let week: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(today)")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.agyBlue)
                Text("today")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(week)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("this week")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.1))
        )
    }
}

struct AIUsageSmallView: View {
    let entry: AIUsageEntry

    var body: some View {
        if let error = entry.error {
            Text(error).font(.system(size: 10)).padding()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Image("AntigravityLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                    Text("Antigravity")
                        .font(.system(size: 12, weight: .bold))
                }
                
                Spacer(minLength: 0)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prompts Today")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("\(entry.stats.promptsToday)")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.agyBlue)
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(.secondary)
                        Text(entry.stats.topWorkspaceToday)
                            .lineLimit(1)
                    }
                    HStack {
                        Image(systemName: "bolt.fill").foregroundStyle(.secondary)
                        Text("\(entry.stats.slashCommandsToday) slash cmds")
                    }
                }
                .font(.system(size: 9, weight: .medium))
            }
            .padding(12)
        }
    }
}

struct AIUsageMediumView: View {
    let entry: AIUsageEntry

    var body: some View {
        if let error = entry.error {
            Text(error).padding()
        } else {
            HStack(spacing: 12) {
                // Left side
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image("AntigravityLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                        Text("Antigravity")
                            .font(.system(size: 14, weight: .bold))
                    }
                    
                    Spacer(minLength: 0)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current Model")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(entry.stats.model)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.agyBlue)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 0)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Top Workspace")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(entry.stats.topWorkspaceToday)
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
                
                // Right side
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading) {
                            Text("Prompts").font(.system(size: 10)).foregroundStyle(.secondary)
                            Text("\(entry.stats.promptsToday)").font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        VStack(alignment: .leading) {
                            Text("Sessions").font(.system(size: 10)).foregroundStyle(.secondary)
                            Text("\(entry.stats.sessionsToday)").font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(Color.agyPurple)
                        Text("\(entry.stats.slashCommandsToday) slash cmds today")
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.agyPurple.opacity(0.1))
                    .cornerRadius(8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
    }
}

struct AIUsageLargeView: View {
    let entry: AIUsageEntry

    var body: some View {
        if let error = entry.error {
            Text(error).padding()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    HStack(spacing: 6) {
                        Image("AntigravityLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                        Text("Antigravity Analytics")
                            .font(.system(size: 16, weight: .bold))
                    }
                    Spacer()
                    Text(entry.date, style: .time)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
                // Model info
                VStack(alignment: .leading, spacing: 4) {
                    Text("CURRENT MODEL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(entry.stats.model)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.agyBlue)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.agyBlue.opacity(0.1))
                        .cornerRadius(8)
                }

                // Grid stats
                HStack(spacing: 12) {
                    StatBox(title: "PROMPTS", today: entry.stats.promptsToday, week: entry.stats.promptsWeek)
                    StatBox(title: "SESSIONS", today: entry.stats.sessionsToday, week: entry.stats.sessionsWeek)
                }
                
                Spacer(minLength: 0)
                
                // Bottom stats
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.secondary)
                        Text("Top Workspace Today:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(entry.stats.topWorkspaceToday)
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                    }
                    
                    Divider()
                    
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(Color.agyPurple)
                        Text("Slash Commands Used:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(entry.stats.slashCommandsToday) today")
                            .font(.system(size: 12, weight: .bold))
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(10)
            }
            .padding(16)
        }
    }
}

// MARK: - Reusable Views (Codex)

struct CodexLimitView: View {
    let title: String
    let percentage: Double
    let resetAt: Date?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                Spacer()
                Text(formatRemainingTime(date: resetAt))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.codexGreen)
                        .frame(width: max(0, min(CGFloat(percentage), 1.0)) * geo.size.width, height: 6)
                }
            }
            .frame(height: 6)
            
            Text("\(Int(percentage * 100))% Used")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct CodexView: View {
    let entry: AIUsageEntry
    let family: WidgetFamily
    
    var body: some View {
        if let error = entry.error {
            Text(error).padding()
        } else {
            let stats = entry.codexStats
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    Image("CodexLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                    Text("Codex Quotas")
                        .font(.system(size: 14, weight: .bold))
                }
                
                Spacer(minLength: 0)
                
                if let pLimit = stats.primaryLimit {
                    CodexLimitView(title: "Primary (\(pLimit))", percentage: stats.primaryUsedPercent ?? 0, resetAt: stats.primaryResetAt)
                } else {
                    Text("No API Data").font(.caption).foregroundStyle(.secondary)
                }
                
                if family != .systemSmall {
                    if let sLimit = stats.secondaryLimit {
                        Spacer(minLength: 4)
                        CodexLimitView(title: "Secondary (\(sLimit))", percentage: stats.secondaryUsedPercent ?? 0, resetAt: stats.secondaryResetAt)
                    }
                }
                
                Spacer(minLength: 0)
                
                if family == .systemLarge {
                    HStack {
                        StatBox(title: "SESSIONS", today: stats.sessionsToday, week: stats.sessionsWeek)
                    }
                } else {
                    HStack {
                        Text("\(stats.sessionsToday) sessions today")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.codexGreen)
                    }
                }
            }
            .padding(family == .systemSmall ? 12 : 16)
        }
    }
}

// MARK: - Widgets

struct AntigravityWidgetEntryView : View {
    var entry: AIUsageProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            AIUsageSmallView(entry: entry)
        case .systemMedium:
            AIUsageMediumView(entry: entry)
        case .systemLarge:
            AIUsageLargeView(entry: entry)
        @unknown default:
            AIUsageSmallView(entry: entry)
        }
    }
}

struct CodexWidgetEntryView : View {
    var entry: AIUsageProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        CodexView(entry: entry, family: family)
    }
}

struct AntigravityWidget: Widget {
    let kind: String = "AntigravityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AIUsageProvider()) { entry in
            AntigravityWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Antigravity Analytics")
        .description("Track your Antigravity usage.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CodexWidget: Widget {
    let kind: String = "CodexWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AIUsageProvider()) { entry in
            CodexWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Codex Quotas")
        .description("Track your Codex quotas.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
