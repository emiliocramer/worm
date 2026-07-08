import SwiftUI

/// Surfaces the Selfie node: the captured face, the worm's read of it, and the
/// concrete observations and aesthetic signals it feeds into the taste profile.
struct SelfieNodeView: View {
    @Environment(SelfieNode.self) private var node

    var body: some View {
        List {
            statusSection

            if let image = node.image {
                Section {
                    HStack {
                        Spacer()
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 160, height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }

            if let analysis = node.analysis {
                readSection(analysis)
            } else if !node.hasSelfie {
                Section {
                    Text("No selfie yet. The worm reads your face during onboarding.")
                        .foregroundStyle(.secondary)
                }
            }

            if let error = node.lastErrorMessage {
                Section("Last error") {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Selfie")
        .toolbar {
            if node.hasSelfie {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await node.syncEverything() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(node.isSyncing)
                }
            }
        }
    }

    // MARK: Sections

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                if node.isSyncing { ProgressView() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.statusSummary).font(.headline)
                    if let read = node.lastAnalyzedAt {
                        Text("Last read \(read.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private func readSection(_ analysis: SelfieAnalysis) -> some View {
        Group {
            Section("The worm's read") {
                Text(analysis.oneLiner)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(analysis.read)
                    .foregroundStyle(.secondary)
            }

            if !analysis.observations.isEmpty {
                Section("Observed") {
                    ForEach(analysis.observations, id: \.self) { Text($0) }
                }
            }

            if !analysis.aesthetics.isEmpty {
                Section("Aesthetic signals") {
                    Text(analysis.aesthetics.joined(separator: ", "))
                }
            }

            Section {
                LabeledContent("Confidence", value: String(format: "%.0f%%", analysis.confidence * 100))
            }
        }
    }
}

#Preview {
    NavigationStack {
        SelfieNodeView()
    }
    .environment(SelfieNode())
}
