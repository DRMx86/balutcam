import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                CameraPreview(cameraController: viewModel.cameraController)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Capture mode")
                            .font(.headline)
                        Spacer()
                        Picker("Mode", selection: $viewModel.captureMode) {
                            ForEach(CaptureMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Film look")
                            .font(.headline)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(viewModel.presetList) { preset in
                                    Button {
                                        viewModel.selectPreset(preset)
                                    } label: {
                                        VStack(alignment: .leading) {
                                            Text(preset.name)
                                                .font(.subheadline.weight(.semibold))
                                            Text("Grain \(preset.grain, specifier: "%.2f")")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 140, alignment: .leading)
                                        .padding(10)
                                        .background(Color(uiColor: .secondarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Adjustments")
                            .font(.headline)

                        ControlSlider(title: "Contrast", value: $viewModel.contrast, range: 0.6...1.8)
                        ControlSlider(title: "Saturation", value: $viewModel.saturation, range: 0.6...1.8)
                        ControlSlider(title: "Brightness", value: $viewModel.brightness, range: -0.5...0.5)
                        ControlSlider(title: "Warmth", value: $viewModel.warmth, range: -0.5...0.5)
                        ControlSlider(title: "Grain", value: $viewModel.grain, range: 0...1)
                        ControlSlider(title: "Vignette", value: $viewModel.vignette, range: 0...1)
                        ControlSlider(title: "LUT strength", value: $viewModel.lutStrength, range: 0...1)
                    }

                    HStack(spacing: 12) {
                        Button(viewModel.captureMode == .video ? "Stop video" : "Capture") {
                            if viewModel.captureMode == .video {
                                viewModel.stopVideoCapture()
                            } else {
                                viewModel.capturePhoto()
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Save preset") {
                            viewModel.saveCustomPreset(name: "Custom \(viewModel.presetList.count + 1)")
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack(spacing: 12) {
                        Button("Select photo") {
                            viewModel.addLibraryItem(MediaAsset(id: UUID(), title: "Imported Photo", kind: .photo, source: "Camera Roll"))
                        }
                        .buttonStyle(.bordered)

                        Button("Select video") {
                            viewModel.addLibraryItem(MediaAsset(id: UUID(), title: "Imported Video", kind: .video, source: "Camera Roll"))
                        }
                        .buttonStyle(.bordered)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Status")
                            .font(.headline)
                        Text(viewModel.status)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.libraryItems) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(item.kind == .photo ? .blue.opacity(0.2) : .purple.opacity(0.23))
                                    .frame(width: 110, height: 110)
                                Text(item.title)
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
            .navigationTitle("BalutCam")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("LUTs") {
                        viewModel.status = "User LUT folder ready"
                    }
                }
            }
        }
    }
}

struct ControlSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2f", value))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}

#Preview {
    ContentView()
}
