//
//  ContentView.swift
//  KegelBump Watch App
//
//  Created by Kevin Kunst on 11/9/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WorkoutSessionViewModel()
    @State private var path: [Destination] = []

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geometry in
                let widthLimit = geometry.size.width
                let heightLimit = geometry.size.height
                let ringSize = min(widthLimit, heightLimit)

                ZStack {
                    Color.black.ignoresSafeArea()

                    VStack(spacing: 12) {
                        CircularProgressView(
                            progress: viewModel.progress,
                            tintColor: viewModel.circleTint,
                            displayNumber: viewModel.displaySeconds,
                            repsDoneText: viewModel.completedRepetitionsText,
                            westContent: AnyView(
                                CornerControlButton(
                                    icon: viewModel.isRunning ? "pause.fill" : "play.fill",
                                    label: viewModel.isRunning ? "Pause" : "Start",
                                    action: viewModel.toggleRunning
                                )
                            ),
                            eastContent: AnyView(
                                CornerControlButton(
                                    icon: "arrow.counterclockwise.circle",
                                    label: "Reset",
                                    action: viewModel.reset
                                )
                            ),
                            southContent: AnyView(
                                IndicatorBadge(
                                    title: "Left",
                                    detail: viewModel.remainingTimeDisplay
                                )
                            ),
                            canvasSize: ringSize,
                            onCenterLongPress: presentEditor
                        )
                        .frame(width: ringSize, height: ringSize)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .editor:
                    SessionEditorView(configuration: viewModel.configuration) { configuration in
                        handleEditorSave(configuration)
                    }
                }
            }
        }
    }

    private func presentEditor() {
        if !path.contains(.editor) {
            path.append(.editor)
        }
    }

    private func handleEditorSave(_ configuration: SessionConfiguration) {
        SessionConfigurationLoader.save(configuration)
        viewModel.updateConfiguration(configuration)
        dismissEditor()
    }

    private func dismissEditor() {
        if let last = path.last, last == .editor {
            path.removeLast()
        } else {
            path.removeAll { $0 == .editor }
        }
    }

    private enum Destination: Hashable {
        case editor
    }
}

private struct CircularProgressView: View {
    var progress: Double
    var tintColor: Color
    var displayNumber: Int
    var repsDoneText: String
    var westContent: AnyView
    var eastContent: AnyView
    var southContent: AnyView
    var canvasSize: CGFloat
    var onCenterLongPress: (() -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let lineWidth = size * 0.12
            let ringColor = Color(red: 255 / 255, green: 149 / 255, blue: 0 / 255)

            ZStack {
                Circle()
                    .stroke(
                        tintColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .animation(.easeInOut(duration: 0.35), value: tintColor.description)

                ProgressArc(progress: progress)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt, lineJoin: .miter)
                    )
                    .animation(.easeInOut(duration: 0.2), value: progress)

                if let onCenterLongPress {
                    Text("\(displayNumber)")
                        .font(.system(size: size * 0.33, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.6) {
                            onCenterLongPress()
                        }
                } else {
                    Text("\(displayNumber)")
                        .font(.system(size: size * 0.33, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }

                CompassIndicators(
                    repsDoneText: repsDoneText,
                    westContent: westContent,
                    eastContent: eastContent,
                    southContent: southContent,
                    canvasSize: canvasSize
                )
            }
            .frame(width: size, height: size)
        }
    }
}

private struct CompassIndicators: View {
    var repsDoneText: String
    var westContent: AnyView
    var eastContent: AnyView
    var southContent: AnyView
    var canvasSize: CGFloat

    var body: some View {
        let radius = canvasSize / 2
        let northOffset = radius * 0.55
        let horizontalOffset = radius * 0.58
        let southOffset = radius * 0.5

        return ZStack {
            RepetitionBadge(text: repsDoneText)
                .offset(y: -northOffset)

            westContent
                .offset(x: -horizontalOffset)

            eastContent
                .offset(x: horizontalOffset)

            southContent
                .offset(y: southOffset)
        }
        .frame(width: canvasSize, height: canvasSize)
    }
}

private struct RepetitionBadge: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
    }
}

private struct IndicatorBadge: View {
    let title: String
    let detail: String
    var width: CGFloat = 60
    var height: CGFloat = 36

    var body: some View {
        VStack(spacing: 1) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.65))

            Text(detail)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
            .frame(width: width, height: height)
    }
}

private struct CornerControlButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)

                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(width: 58, height: 58)
        }
        .buttonStyle(.plain)
    }
}

private struct ProgressArc: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard progress > 0 else { return path }

        let startAngle = Angle(degrees: -90)
        let endAngle = Angle(degrees: -90 + progress * 360)
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)

        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }
}

#Preview {
    ContentView()
}
