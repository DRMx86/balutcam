import SwiftUI

struct CameraScreen: View {
    @EnvironmentObject var look: LookStore
    @EnvironmentObject var presets: PresetStore
    @EnvironmentObject var settings: AppSettings
    @StateObject private var camera = CameraService()
    @AppStorage("balutcam.showAdjust") private var showAdjust = false
    @State private var showEditor = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()

                if camera.permissionDenied {
                    permissionView
                } else {
                    // The preview fills the whole screen; controls float on top of it.
                    CameraPreview(service: camera).ignoresSafeArea()
                    if landscape { landscapeLayout } else { portraitLayout }
                }

                if let message = camera.message {
                    VStack {
                        if !landscape { Spacer() }
                        Text(message)
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(landscape ? .top : .bottom, landscape ? 70 : 230)
                        if landscape { Spacer() }
                    }
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: camera.message)
        .onAppear { camera.bind(look: look, settings: settings); camera.start() }
        .onChange(of: showEditor) { open in open ? camera.stop() : camera.start() }
        .onChange(of: settings.config.frameRate) { _ in camera.applyFrameRate() }
        .fullScreenCover(isPresented: $showEditor) {
            EditorScreen()
                .environmentObject(look)
                .environmentObject(presets)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
        }
    }

    // MARK: Layouts

    private var portraitLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                topItems(landscape: false)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom))

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                if showAdjust {
                    ControlsPanel()
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 8)
                } else {
                    PresetStrip()
                }
                modePicker(vertical: false)
                HStack {
                    libraryButton
                    Spacer()
                    shutter
                    Spacer()
                    adjustButton
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 12).padding(.bottom, 8)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
        }
    }

    private var landscapeLayout: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) { topItems(landscape: true) }
                    .padding(.top, 4)
                if showAdjust {
                    ControlsPanel()
                        .frame(width: 380)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                Spacer(minLength: 0)
                modePicker(vertical: true)
                shutter
                HStack(spacing: 14) {
                    libraryButton
                    adjustButton
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    // MARK: Pieces

    @ViewBuilder
    private func topItems(landscape: Bool) -> some View {
        roundButton(settings.config.flashOn ? "bolt.fill" : "bolt.slash") {
            settings.config.flashOn.toggle()
        }
        Menu {
            Picker("Format", selection: $settings.config.format) {
                ForEach(OutputFormat.allCases) { f in
                    Text("\(f.label(landscape: landscape)) · \(f.detail(landscape: landscape))").tag(f)
                }
            }
        } label: {
            pill(settings.config.format.label(landscape: landscape), icon: "aspectratio")
        }
        .disabled(camera.isRecording)

        if settings.config.mode == .video {
            Menu {
                Picker("Frame rate", selection: $settings.config.frameRate) {
                    ForEach(FrameRate.allCases) { r in Text("\(r.label) fps").tag(r) }
                }
            } label: {
                pill("\(settings.config.frameRate.label) fps", icon: "film")
            }
            .disabled(camera.isRecording)
        }

        if !landscape { Spacer(minLength: 0) }
        if !landscape { Text(activeName).font(.footnote.weight(.semibold)).foregroundColor(.orange).lineLimit(1) }
        if !landscape { Spacer(minLength: 0) }

        roundButton("arrow.triangle.2.circlepath.camera") { camera.flipCamera() }
            .disabled(camera.isRecording)
    }

    private var activeName: String {
        if let id = look.activePresetID, let p = presets.all.first(where: { $0.id == id }) { return p.name }
        return look.params.lutName.map { "LUT: \($0)" } ?? "Custom"
    }

    private func roundButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(Color.black.opacity(0.45), in: Circle())
        }
    }

    private func pill(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text).font(.callout.weight(.bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .frame(height: 56)
        .background(Color.black.opacity(0.45), in: Capsule())
    }

    private func modePicker(vertical: Bool) -> some View {
        let buttons = ForEach(CaptureMode.allCases) { m in
            Button { settings.config.mode = m } label: {
                Text(m.rawValue)
                    .font(.callout.weight(.bold))
                    .foregroundColor(settings.config.mode == m ? .black : .white)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(settings.config.mode == m ? Color.yellow : Color.black.opacity(0.45), in: Capsule())
            }
        }
        return Group {
            if vertical { VStack(spacing: 8) { buttons } } else { HStack(spacing: 12) { buttons } }
        }
        .disabled(camera.isRecording)
    }

    private var libraryButton: some View {
        roundButton("photo.on.rectangle") { showEditor = true }
            .disabled(camera.isRecording)
    }

    private var adjustButton: some View {
        Button { withAnimation { showAdjust.toggle() } } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(showAdjust ? .black : .white)
                .frame(width: 56, height: 56)
                .background(showAdjust ? Color.orange : Color.black.opacity(0.45), in: Circle())
        }
    }

    private var shutter: some View {
        Button {
            if settings.config.mode == .photo { camera.capturePhoto() } else { camera.toggleRecording() }
        } label: {
            ZStack {
                Circle().stroke(Color.white, lineWidth: 5).frame(width: 86, height: 86)
                if settings.config.mode == .photo {
                    Circle().fill(Color.white).frame(width: 70, height: 70)
                } else if camera.isRecording {
                    RoundedRectangle(cornerRadius: 8).fill(Color.red).frame(width: 36, height: 36)
                } else {
                    Circle().fill(Color.red).frame(width: 70, height: 70)
                }
            }
            .overlay(alignment: .top) {
                if camera.isRecording {
                    Text(String(format: "%02d:%02d", camera.recordingSeconds / 60, camera.recordingSeconds % 60))
                        .font(.caption.monospacedDigit().weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.red, in: Capsule())
                        .foregroundColor(.white)
                        .offset(y: -30)
                }
            }
        }
    }

    private var permissionView: some View {
        VStack(spacing: 14) {
            Text("Camera access is off").font(.headline)
            Text("Enable camera access for BalutCam in Settings.")
                .font(.subheadline).foregroundColor(.gray)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Edit existing media instead") { showEditor = true }
        }
        .foregroundColor(.white)
    }
}
