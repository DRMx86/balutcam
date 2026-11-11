import SwiftUI

struct CameraScreen: View {
    @EnvironmentObject var look: LookStore
    @EnvironmentObject var presets: PresetStore
    @StateObject private var camera = CameraService()
    @State private var showAdjust = false
    @State private var showEditor = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.permissionDenied {
                VStack(spacing: 12) {
                    Text("Camera access is off").font(.headline)
                    Text("Enable camera access for BalutCam in Settings.")
                        .font(.subheadline).foregroundColor(.gray)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    Button("Edit existing media instead") { showEditor = true }
                }
                .foregroundColor(.white)
            } else {
                VStack(spacing: 0) {
                    topBar
                    ZStack(alignment: .top) {
                        CameraPreview(service: camera)
                        if camera.isRecording { recordingBadge.padding(.top, 8) }
                    }
                    bottom
                }
            }

            if let message = camera.message {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 180)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: camera.message)
        .onAppear { camera.bind(look); camera.start() }
        .onChange(of: showEditor) { open in open ? camera.stop() : camera.start() }
        .fullScreenCover(isPresented: $showEditor) {
            EditorScreen()
                .environmentObject(look)
                .environmentObject(presets)
                .preferredColorScheme(.dark)
        }
    }

    private var topBar: some View {
        HStack {
            Button { camera.flashOn.toggle() } label: {
                Image(systemName: camera.flashOn ? "bolt.fill" : "bolt.slash")
            }
            Spacer()
            Text(activeName).font(.footnote.weight(.semibold)).foregroundColor(.orange)
            Spacer()
            Button { camera.flipCamera() } label: { Image(systemName: "arrow.triangle.2.circlepath.camera") }
                .disabled(camera.isRecording)
        }
        .font(.title3)
        .foregroundColor(.white)
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private var activeName: String {
        if let id = look.activePresetID, let p = presets.all.first(where: { $0.id == id }) { return p.name }
        return look.params.lutName.map { "LUT: \($0)" } ?? "Custom"
    }

    private var recordingBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
            Text(String(format: "%02d:%02d", camera.recordingSeconds / 60, camera.recordingSeconds % 60))
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.black.opacity(0.6), in: Capsule())
        .foregroundColor(.white)
    }

    private var bottom: some View {
        VStack(spacing: 10) {
            if showAdjust {
                ControlsPanel().frame(height: 250)
            } else {
                PresetStrip().padding(.top, 6)
            }

            HStack(spacing: 28) {
                ForEach(CameraService.Mode.allCases) { m in
                    Button(m.rawValue) { camera.mode = m }
                        .font(.footnote.weight(.bold))
                        .foregroundColor(camera.mode == m ? .yellow : .white)
                }
            }
            .disabled(camera.isRecording)

            HStack {
                Button { showEditor = true } label: {
                    Image(systemName: "photo.on.rectangle").font(.title2)
                        .frame(width: 60, height: 60)
                }
                .disabled(camera.isRecording)
                Spacer()
                shutter
                Spacer()
                Button { withAnimation { showAdjust.toggle() } } label: {
                    Image(systemName: "slider.horizontal.3").font(.title2)
                        .foregroundColor(showAdjust ? .orange : .white)
                        .frame(width: 60, height: 60)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .background(Color.black)
    }

    private var shutter: some View {
        Button {
            if camera.mode == .photo { camera.capturePhoto() } else { camera.toggleRecording() }
        } label: {
            ZStack {
                Circle().stroke(Color.white, lineWidth: 4).frame(width: 74, height: 74)
                if camera.mode == .photo {
                    Circle().fill(Color.white).frame(width: 60, height: 60)
                } else if camera.isRecording {
                    RoundedRectangle(cornerRadius: 6).fill(Color.red).frame(width: 30, height: 30)
                } else {
                    Circle().fill(Color.red).frame(width: 60, height: 60)
                }
            }
        }
    }
}
