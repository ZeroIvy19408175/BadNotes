//
//  AppLog.swift
//  BadNotes
//
//  앱 전체 로그. 에러가 생기면 화면 아래 빨간 배너로 바로 띄움.
//

import SwiftUI
import Observation

@Observable
final class AppLog {
    static let shared = AppLog()

    enum Level: String { case info = "INFO", warn = "WARN", error = "ERROR" }

    struct Entry: Identifiable {
        let id = UUID()
        let date = Date()
        let level: Level
        let message: String
    }

    private(set) var entries: [Entry] = []
    /// 아직 확인 안 한 최신 에러 (배너용)
    var latestError: Entry?
    var unreadErrors = 0

    func info(_ msg: LocalizedStringResource)  { add(.info, String(localized: msg)) }
    func warn(_ msg: LocalizedStringResource)  { add(.warn, String(localized: msg)) }
    func error(_ msg: LocalizedStringResource) { add(.error, String(localized: msg)) }

    private func add(_ level: Level, _ msg: String) {
        let e = Entry(level: level, message: msg)
        print("[\(level.rawValue)] \(msg)")
        DispatchQueue.main.async {
            self.entries.append(e)
            if self.entries.count > 500 { self.entries.removeFirst(self.entries.count - 500) }
            if level == .error {
                self.latestError = e
                self.unreadErrors += 1
            }
        }
    }

    func markRead() { unreadErrors = 0; latestError = nil }
    func clear() { entries.removeAll(); markRead() }

    var exportText: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        return entries.map { "\(f.string(from: $0.date)) [\($0.level.rawValue)] \($0.message)" }
            .joined(separator: "\n")
    }
}

struct LogView: View {
    @Environment(\.dismiss) private var dismiss
    var log = AppLog.shared
    @State private var errorsOnly = false

    var body: some View {
        NavigationStack {
            List(log.entries.reversed().filter { !errorsOnly || $0.level == .error }) { e in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(e.level.rawValue)
                            .font(.caption.bold())
                            .foregroundStyle(color(e.level))
                        Text(e.date, format: .dateTime.hour().minute().second())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(e.message).font(.callout.monospaced()).textSelection(.enabled)
                }
            }
            .overlay {
                if log.entries.isEmpty {
                    ContentUnavailableView("로그 없음", systemImage: "checkmark.circle")
                }
            }
            .navigationTitle("로그")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Toggle("에러만", isOn: $errorsOnly).toggleStyle(.button)
                    Button("복사") { UIPasteboard.general.string = log.exportText }
                    Button("지우기", role: .destructive) { log.clear() }
                }
            }
        }
        .onAppear { log.markRead() }
    }

    func color(_ l: AppLog.Level) -> Color {
        switch l { case .info: .secondary; case .warn: .orange; case .error: .red }
    }
}
