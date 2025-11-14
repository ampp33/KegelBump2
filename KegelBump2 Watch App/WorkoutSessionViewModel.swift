//
//  WorkoutSessionViewModel.swift
//  KegelBump Watch App
//
//  Created by Codex on 11/9/25.
//

import SwiftUI
import Combine
import WatchKit

struct SessionPhase: Identifiable {
    enum PhaseType: String, Codable {
        case hold
        case rest

        var displayName: String {
            switch self {
            case .hold:
                return "Hold"
            case .rest:
                return "Rest"
            }
        }

        var tint: Color {
            switch self {
            case .hold:
                return Color.green
            case .rest:
                return Color.red
            }
        }
    }

    let id = UUID()
    let type: PhaseType
    let duration: Int
    let setIndex: Int
    let totalSets: Int
    let phasePositionInSet: Int
    let phaseCountInSet: Int
}

struct SessionConfiguration: Codable {
    struct Block: Codable {
        let repeatCount: Int
        let phases: [PhaseTemplate]
    }

    struct PhaseTemplate: Codable {
        let type: SessionPhase.PhaseType
        let duration: Int
    }

    let blocks: [Block]

    func expandedPhases() -> [SessionPhase] {
        var items: [SessionPhase] = []
        let totalSetCount = blocks.reduce(0) { $0 + max(0, $1.repeatCount) }
        guard totalSetCount > 0 else { return items }

        var setCounter = 0

        for block in blocks {
            guard block.repeatCount > 0 else { continue }
            for _ in 0..<block.repeatCount {
                setCounter += 1
                for (phaseIndex, phase) in block.phases.enumerated() {
                    items.append(
                        SessionPhase(
                            type: phase.type,
                            duration: phase.duration,
                            setIndex: setCounter,
                            totalSets: totalSetCount,
                            phasePositionInSet: phaseIndex,
                            phaseCountInSet: block.phases.count
                        )
                    )
                }
            }
        }
        return items
    }

    static var fallback: SessionConfiguration {
        SessionConfiguration(
            blocks: [
                .init(
                    repeatCount: 10,
                    phases: [
                        .init(type: .hold, duration: 7),
                        .init(type: .rest, duration: 7)
                    ]
                ),
                .init(
                    repeatCount: 10,
                    phases: [
                        .init(type: .hold, duration: 2),
                        .init(type: .rest, duration: 2)
                    ]
                )
            ]
        )
    }
}

enum SessionConfigurationLoader {
    static func load() -> SessionConfiguration {
        if let customURL = writableURL,
           let customData = try? Data(contentsOf: customURL),
           let configuration = try? JSONDecoder().decode(SessionConfiguration.self, from: customData) {
            return configuration
        }

        guard let url = Bundle.main.url(forResource: "SessionConfiguration", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return SessionConfiguration.fallback
        }

        do {
            let configuration = try JSONDecoder().decode(SessionConfiguration.self, from: data)
            return configuration
        } catch {
            return SessionConfiguration.fallback
        }
    }

    static func save(_ configuration: SessionConfiguration) {
        guard let url = writableURL else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(configuration)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save session configuration: \(error)")
        }
    }

    private static var writableURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("SessionConfiguration.json")
    }
}

@MainActor
final class WorkoutSessionViewModel: ObservableObject {
    @Published private(set) var configuration: SessionConfiguration
    @Published private(set) var phases: [SessionPhase] = []
    @Published private(set) var currentPhaseIndex: Int = 0
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isComplete: Bool = false
    @Published private(set) var sessionStarted: Bool = false

    private var timer: Timer?
    private var totalSessionDuration: Int = 0

    init(configuration: SessionConfiguration = SessionConfigurationLoader.load()) {
        self.configuration = configuration
        applyConfiguration(configuration)
    }

    deinit {
        timer?.invalidate()
    }

    var currentPhase: SessionPhase? {
        guard phases.indices.contains(currentPhaseIndex) else { return nil }
        return phases[currentPhaseIndex]
    }

    var nextPhase: SessionPhase? {
        let nextIndex = currentPhaseIndex + 1
        guard phases.indices.contains(nextIndex) else { return nil }
        return phases[nextIndex]
    }

    var displayPhaseName: String {
        if isComplete {
            return "Complete"
        }

        if let phase = currentPhase {
            return phase.type.displayName
        }

        return "Ready"
    }

    var circleTint: Color {
        guard sessionStarted, !isComplete, let phase = currentPhase else {
            return Color(red: 255 / 255, green: 149 / 255, blue: 0 / 255)
        }

        return phase.type.tint
    }

    var completedRepetitionsText: String {
        return "\(completedRepetitions)/\(totalSets)"
    }

    var remainingTimeDisplay: String {
        SessionTimeFormatter.string(from: sessionRemainingSeconds)
    }

    var elapsedTimeDisplay: String {
        SessionTimeFormatter.string(from: sessionElapsedSeconds)
    }

    var nextPhaseTitle: String {
        nextPhase?.type.displayName ?? "Next"
    }

    var nextPhaseDetail: String {
        guard let nextPhase else { return "--" }
        return "\(nextPhase.duration)s"
    }

    private var totalSets: Int {
        phases.last?.totalSets ?? currentPhase?.totalSets ?? 0
    }

    private var completedRepetitions: Int {
        if isComplete {
            return totalSets
        }

        guard sessionStarted, let currentSet = currentPhase?.setIndex else {
            return 0
        }

        return max(0, currentSet - 1)
    }

    private var sessionRemainingSeconds: Int {
        guard !phases.isEmpty else { return 0 }
        let futurePhases = phases.dropFirst(currentPhaseIndex + 1).reduce(0) { $0 + $1.duration }
        return futurePhases + remainingSeconds
    }

    private var sessionElapsedSeconds: Int {
        max(0, totalSessionDuration - sessionRemainingSeconds)
    }

    var displaySeconds: Int {
        if isComplete {
            return 0
        }

        if sessionStarted {
            return remainingSeconds
        }

        return currentPhase?.duration ?? 0
    }

    var progress: Double {
        if isComplete {
            return 1.0
        }

        guard sessionStarted,
              let phase = currentPhase,
              phase.duration > 0 else {
            return 0
        }

        let elapsed = phase.duration - remainingSeconds
        let clamped = max(0, min(Double(elapsed) / Double(phase.duration), 1))
        return clamped
    }

    func toggleRunning() {
        if isComplete {
            reset()
        }

        isRunning ? pause() : start()
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        isComplete = false
        sessionStarted = false
        currentPhaseIndex = 0
        remainingSeconds = phases.first?.duration ?? 0
    }

    private func start() {
        guard !phases.isEmpty else { return }
        sessionStarted = true
        isRunning = true
        scheduleTimer()
    }

    private func pause() {
        isRunning = false
        timer?.invalidate()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handleTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func handleTick() {
        guard isRunning else { return }

        SessionHaptics.tick()

        if remainingSeconds > 0 {
            remainingSeconds -= 1
            return
        }

        advancePhase()
    }

    private func advancePhase() {
        SessionHaptics.phaseComplete()

        if currentPhaseIndex + 1 < phases.count {
            currentPhaseIndex += 1
            remainingSeconds = phases[currentPhaseIndex].duration
        } else {
            completeSession()
        }
    }

    private func completeSession() {
        isRunning = false
        isComplete = true
        remainingSeconds = 0
        timer?.invalidate()
    }

    func updateConfiguration(_ configuration: SessionConfiguration) {
        self.configuration = configuration
        applyConfiguration(configuration)
    }

    private func applyConfiguration(_ configuration: SessionConfiguration) {
        let loadedPhases = configuration.expandedPhases()
        phases = loadedPhases
        totalSessionDuration = loadedPhases.reduce(0) { $0 + $1.duration }
        reset()
    }
}

private enum SessionHaptics {
    static func tick() {
        WKInterfaceDevice.current().play(.click)
    }

    static func phaseComplete() {
        WKInterfaceDevice.current().play(.directionUp)
    }
}

enum SessionTimeFormatter {
    static func string(from seconds: Int) -> String {
        guard seconds > 0 else { return "0s" }
        let minutes = seconds / 60
        let remainder = seconds % 60

        if minutes == 0 {
            return "\(remainder)s"
        } else {
            return String(format: "%d:%02d", minutes, remainder)
        }
    }
}
