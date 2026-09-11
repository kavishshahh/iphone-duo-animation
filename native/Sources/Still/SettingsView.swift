import SwiftUI
import FoldCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 22) {
            HStack(alignment: .center) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 50, height: 50)
                    .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Still").font(.system(size: 27, weight: .semibold))
                    Text("A little wonder in every fold.").foregroundStyle(.secondary)
                }
                Spacer()
                Text("FREE PROTOTYPE").font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.quaternary, in: Capsule())
            }

            ZStack(alignment: .bottomTrailing) {
                MetalPreview(angle: model.previewAngle, tuning: model.tuning)
                    .aspectRatio(1.6, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.15)))
                Text("\(Int(model.previewAngle))°")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.black.opacity(0.35), in: Capsule())
                    .padding(14)
            }
            .frame(maxHeight: 270)

            HStack(spacing: 16) {
                Button {
                    model.playingPreview ? model.stopPreview() : model.playPreview()
                } label: {
                    Label(model.playingPreview ? "Pause" : "Play", systemImage: model.playingPreview ? "pause.fill" : "play.fill")
                }
                .frame(width: 90)
                Text("Closed").foregroundStyle(.secondary)
                Slider(value: $model.previewAngle, in: 18...model.tuning.workingAngle) { editing in
                    if editing { model.stopPreview() }
                }.accessibilityLabel("Preview lid angle")
                Text("Open").foregroundStyle(.secondary)
            }

            Picker("Settings", selection: $selectedTab) {
                Text("Appearance").tag(0)
                Text("Your Mac").tag(1)
            }.pickerStyle(.segmented).frame(width: 270)

            Group {
                if selectedTab == 0 {
                    VStack(spacing: 14) {
                        HStack {
                            Text("Look").frame(width: 100, alignment: .leading)
                            ForEach(["Clear", "Frost", "Soft"], id: \.self) { style in
                                Button(style) { model.applyPreset(style) }
                                    .buttonStyle(.bordered)
                            }
                            Spacer()
                            Button("Reset") { model.reset() }.buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                        tuningSlider("Perspective", value: $model.tuning.perspective)
                        tuningSlider("Frost", value: $model.tuning.frost)
                        tuningSlider("Shadow", value: $model.tuning.shade)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.sensorMessage).fontWeight(.medium)
                                Text(model.modelIdentifier).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Rescan") { model.rescan() }
                        }
                        HStack {
                            Text("Working angle")
                            Slider(value: $model.tuning.workingAngle, in: 75...135, step: 1)
                            Text("\(Int(model.tuning.workingAngle))°").monospacedDigit().frame(width: 40)
                            Button("Use current lid") { model.calibrate() }.disabled(model.sensorAngle == nil)
                        }
                        HStack {
                            Label(model.captureAllowed ? "Screen Recording allowed" : "Screen Recording needed for desktop mode",
                                  systemImage: model.captureAllowed ? "checkmark.circle" : "rectangle.dashed")
                            Spacer()
                            Button(model.captureAllowed ? "Settings" : "Allow") {
                                model.captureAllowed ? model.openCaptureSettings() : model.requestCaptureAccess()
                            }
                        }
                        Text("M1 Air and 13-inch M1/M2 Pro can use the manual demo. Automatic mode needs a readable hinge sensor.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.frame(height: 158)

            Divider()
            HStack {
                Toggle("Follow lid", isOn: $model.automaticEnabled)
                    .toggleStyle(.switch)
                    .disabled(model.sensorAngle == nil || !model.captureAllowed)
                Spacer()
                if model.isBusy {
                    Button("Stop preview") { model.pause() }
                } else {
                    Button("Preview on desktop") { model.playDesktopDemo() }
                        .buttonStyle(.borderedProminent)
                }
            }
            Text(model.message).font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).lineLimit(2)
        }
        .padding(28)
        .frame(width: 764)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand { model.pause() }
    }

    private func tuningSlider(_ label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 16) {
            Text(label).frame(width: 100, alignment: .leading)
            Slider(value: value, in: 0...1).accessibilityLabel(label)
            Text("\(Int(value.wrappedValue * 100))%").monospacedDigit()
                .foregroundStyle(.secondary).frame(width: 45, alignment: .trailing)
        }
    }
}
