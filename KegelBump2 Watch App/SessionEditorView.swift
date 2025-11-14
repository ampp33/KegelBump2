//
//  SessionEditorView.swift
//  KegelBump Watch App
//
//  Created by Codex on 11/9/25.
//

import SwiftUI

struct SessionEditorView: View {
    @State private var blocks: [EditableSessionBlock]
    let onBack: (SessionConfiguration) -> Void

    init(configuration: SessionConfiguration, onBack: @escaping (SessionConfiguration) -> Void) {
        _blocks = State(initialValue: configuration.blocks.map(EditableSessionBlock.init))
        self.onBack = onBack
    }

    var body: some View {
        VStack(spacing: 12) {
            header

            List {
                ForEach(blocks.indices, id: \.self) { index in
                    SessionBlockRow(block: $blocks[index])
                        .listRowBackground(Color.black)
                        .overlay(alignment: .bottom) {
                            if index < blocks.count - 1 {
                                Rectangle()
                                    .fill(Color(red: 255 / 255, green: 149 / 255, blue: 0 / 255).opacity(1))
                                    .frame(height: 1)
                                    .padding(.horizontal, 6)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteBlock(at: index)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }

                Button(action: addBlock) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                        Text("Add Block")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color(red: 255 / 255, green: 149 / 255, blue: 0 / 255).opacity(1))
            }
            .listStyle(.plain)
        }
        .padding(.top, 0)
        .navigationBarBackButtonHidden(true)
        .background(Color.black.ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            Button(action: handleBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(0)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Customize")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            Spacer()

            // Invisible spacer to balance the header layout
            Color.clear.frame(width: 60, height: 1)
        }
        .padding(.horizontal)
    }

    private func deleteBlock(at index: Int) {
        guard blocks.indices.contains(index) else { return }
        blocks.remove(at: index)
    }

    private func addBlock() {
        blocks.append(.defaultBlock)
    }

    private func handleBack() {
        let configuration = SessionConfiguration(blocks: blocks.map { $0.makeBlock() })
        onBack(configuration)
    }
}

private struct SessionBlockRow: View {
    @Binding var block: EditableSessionBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AdjustmentLine(
                label: "\(block.repeatCount) Reps",
                font: .system(size: 14, weight: .semibold),
                color: .white,
                onIncrement: { block.repeatCount += 1 },
                onDecrement: { block.repeatCount = max(1, block.repeatCount - 1) }
            )

            AdjustmentLine(
                label: "\(block.holdDuration)s hold",
                font: .system(size: 12, weight: .medium),
                color: .gray,
                onIncrement: { block.holdDuration += 1 },
                onDecrement: { block.holdDuration = max(1, block.holdDuration - 1) }
            )

            AdjustmentLine(
                label: "\(block.restDuration)s rest",
                font: .system(size: 12, weight: .medium),
                color: .gray,
                onIncrement: { block.restDuration += 1 },
                onDecrement: { block.restDuration = max(1, block.restDuration - 1) }
            )
        }
        .padding(.vertical, 4)
    }
}

private struct AdjustmentLine: View {
    let label: String
    let font: Font
    let color: Color
    let onIncrement: () -> Void
    let onDecrement: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            StepIconButton(systemImage: "plus.circle.fill", action: onIncrement)

            Text(label)
                .font(font)
                .foregroundStyle(color)

            Spacer()

            StepIconButton(systemImage: "minus.circle.fill", action: onDecrement)
        }
    }
}

private struct StepIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
}

struct EditableSessionBlock: Identifiable, Equatable {
    let id: UUID
    var repeatCount: Int
    var holdDuration: Int
    var restDuration: Int

    init(id: UUID = UUID(), repeatCount: Int, holdDuration: Int, restDuration: Int) {
        self.id = id
        self.repeatCount = max(1, repeatCount)
        self.holdDuration = max(1, holdDuration)
        self.restDuration = max(1, restDuration)
    }

    init(block: SessionConfiguration.Block) {
        let hold = block.phases.first(where: { $0.type == .hold })?.duration ?? 1
        let rest = block.phases.first(where: { $0.type == .rest })?.duration ?? 1
        self.init(repeatCount: block.repeatCount, holdDuration: hold, restDuration: rest)
    }

    func makeBlock() -> SessionConfiguration.Block {
        SessionConfiguration.Block(
            repeatCount: max(1, repeatCount),
            phases: [
                SessionConfiguration.PhaseTemplate(type: .hold, duration: max(1, holdDuration)),
                SessionConfiguration.PhaseTemplate(type: .rest, duration: max(1, restDuration))
            ]
        )
    }

    static var defaultBlock: EditableSessionBlock {
        EditableSessionBlock(repeatCount: 10, holdDuration: 5, restDuration: 5)
    }
}

#Preview {
    NavigationStack {
        SessionEditorView(configuration: SessionConfiguration.fallback) { _ in }
    }
}
