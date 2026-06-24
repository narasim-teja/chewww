//
//  ContentView.swift
//  chewww
//
//  Phase 1: labeled-dataset collector. Pick ONE label (and, for eating, an
//  optional texture) BEFORE recording — the record button stays disabled
//  until a label is chosen. Live sample rate (Hz), buds in/out status, sample
//  count, Start/Stop, Share, and a History link to browse collected sessions.
//

import SwiftUI

struct ContentView: View {
    @State private var vm = RecorderViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    statusCard
                    if !vm.recording {
                        labelPicker
                        if vm.selectedLabel?.supportsTexture == true {
                            texturePicker
                        }
                    }
                    liveReadout
                    recordButton
                    shareButton
                }
                .padding()
            }
            .navigationTitle("chewww")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SessionHistoryView()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
            .onAppear { vm.refreshAvailability() }
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label {
                    Text(vm.connected ? "AirPods connected" : "No AirPods motion")
                } icon: {
                    Image(systemName: vm.connected ? "airpodspro" : "airpods.gen3")
                        .foregroundStyle(vm.connected ? .green : .secondary)
                }
                Spacer()
                Text("auth: \(vm.authorizationText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(vm.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Label picker (grid of the six labels)

    private var labelPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Label")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)],
                      spacing: 12) {
                ForEach(SessionLabel.allCases) { label in
                    labelTile(label)
                }
            }
        }
    }

    private func labelTile(_ label: SessionLabel) -> some View {
        let isSelected = vm.selectedLabel == label
        return Button {
            withAnimation { vm.select(label) }   // animate the texture row in/out
        } label: {
            VStack(spacing: 6) {
                Image(systemName: label.systemImage)
                    .font(.title2)
                Text(label.title)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Texture picker (only when eating)

    private var texturePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Texture")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Texture", selection: $vm.selectedTexture) {
                ForEach(FoodTexture.allCases) { texture in
                    Text(texture.title).tag(texture)
                }
            }
            .pickerStyle(.segmented)
        }
        .transition(.opacity)
    }

    // MARK: - Live numbers

    private var liveReadout: some View {
        VStack(spacing: 8) {
            Text(String(format: "%.1f", vm.sampleRateHz))
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("Hz")
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                metric("samples", "\(vm.sampleCount)")
                if let s = vm.lastSample {
                    metric("bud", s.sensorLocation)
                }
            }
            .padding(.top, 8)

            // Tiny peek at the live accel signal — the chewing candidate.
            if let s = vm.lastSample {
                Text(String(format: "acc  x %+.3f   y %+.3f   z %+.3f",
                            s.accX, s.accY, s.accZ))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack {
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Buttons

    private var recordButton: some View {
        Button(action: vm.toggleRecording) {
            Text(vm.recording ? "Stop" : "Start Recording")
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundStyle(.white)
                .background(vm.recording ? Color.red
                            : (vm.canRecord ? Color.accentColor : Color.gray),
                            in: RoundedRectangle(cornerRadius: 16))
        }
        // Always allow Stop; block Start until a label is picked + motion ready.
        .disabled(!vm.recording && !vm.canRecord)
    }

    private var shareButton: some View {
        Group {
            if let url = vm.lastFileURL, !vm.recording {
                ShareLink(item: url) {
                    Label("Share last CSV", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
