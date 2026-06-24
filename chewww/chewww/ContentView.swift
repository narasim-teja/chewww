//
//  ContentView.swift
//  chewww
//
//  Phase 0 spike UI: start/stop recording, live sample rate (Hz), buds in/out
//  status, sample count, and a Share button to get the CSV off-device.
//

import SwiftUI

struct ContentView: View {
    @State private var vm = RecorderViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                statusCard
                liveReadout
                Spacer()
                recordButton
                shareButton
            }
            .padding()
            .navigationTitle("chewww")
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
                .background(vm.recording ? Color.red : Color.accentColor,
                            in: RoundedRectangle(cornerRadius: 16))
        }
        .disabled(!vm.motionAvailable && !vm.recording)
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
