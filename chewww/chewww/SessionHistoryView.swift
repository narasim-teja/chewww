//
//  SessionHistoryView.swift
//  chewww
//
//  On-device list of recorded CSVs. The list IS the Documents directory:
//  we re-scan on appear, on pull-to-refresh, and when the app returns to the
//  foreground, so it always matches disk — including files added/removed via
//  the Files app. Per-row ShareLink gets a CSV off-device; swipe-to-delete
//  removes the file.
//
//  Presented from ContentView via a toolbar button + NavigationLink (the
//  app's existing NavigationStack). No view model needed — this screen is
//  read-mostly and its only mutation (delete) is a single FileManager call.
//

import SwiftUI

struct SessionHistoryView: View {
    @State private var sessions: [RecordedSession] = []
    @State private var isLoading = true
    @State private var deleteError: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .task { await reload() }                 // first load (async, off-main scan)
            .refreshable { await reload() }          // pull-to-refresh
            .onChange(of: scenePhase) { _, phase in  // catch Files-app edits on foreground
                if phase == .active { Task { await reload() } }
            }
            .alert("Couldn't delete file",
                   isPresented: Binding(get: { deleteError != nil },
                                        set: { if !$0 { deleteError = nil } })) {
                Button("OK", role: .cancel) { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Scanning…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sessions.isEmpty {
            ContentUnavailableView(
                "No recordings yet",
                systemImage: "waveform.path.ecg",
                description: Text("Recorded sessions will appear here.")
            )
        } else {
            List {
                Section {
                    ForEach(sessions) { session in
                        row(session)
                    }
                    .onDelete(perform: delete)
                } footer: {
                    Text("^[\(sessions.count) session](inflect: true)")
                }
            }
        }
    }

    // MARK: - Row

    private func row(_ session: RecordedSession) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayLabel)
                    .font(.headline)
                Text(session.dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Label("\(session.sampleCount)", systemImage: "number")
                    Label(session.durationText, systemImage: "clock")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            Spacer()
            // Per-row share — same affordance as the main screen's ShareLink.
            // .borderless keeps the tap on the icon, not the whole cell.
            ShareLink(item: session.fileURL) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Mutations

    private func reload() async {
        let loaded = await RecordedSession.loadAll()
        sessions = loaded
        isLoading = false
    }

    private func delete(at offsets: IndexSet) {
        let fm = FileManager.default
        var failed = false
        // Delete each file first; only drop rows whose file actually went away,
        // so the UI never claims a still-present file is gone.
        let targets = offsets.map { sessions[$0] }
        for session in targets {
            do {
                try fm.removeItem(at: session.fileURL)
            } catch {
                failed = true
            }
        }
        if failed {
            deleteError = "One or more files couldn't be removed."
        }
        // Re-derive from disk so the list and disk can never disagree.
        Task { await reload() }
    }
}

#Preview {
    NavigationStack { SessionHistoryView() }
}
