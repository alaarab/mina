import PhotosUI
import SwiftUI
import UIKit

/// The photo pieces shared by the note sheet, the editor and the rows: an
/// "Add photo" control that takes a picture or picks one, the thumbnail a row
/// shows, and the full-screen viewer either opens. Everything a picker hands
/// back goes through `PhotoStore` before it is kept, so the log only ever
/// holds a downscaled JPEG with no metadata.

// MARK: Attach

/// Add, replace or remove a picture on a draft. Shows the chosen picture with
/// an x to remove it; tapping the picture opens the viewer.
struct PhotoAttachment: View {
    @Binding var photo: EntryPhoto?
    var tint: Color = MinaTheme.accent

    @State private var pickerItem: PhotosPickerItem?
    @State private var choosing = false
    @State private var takingPhoto = false
    @State private var viewing = false
    @State private var preparing = false

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        Group {
            if let photo, let image = UIImage(data: photo.full) {
                HStack(alignment: .top, spacing: 12) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onTapGesture { viewing = true }
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(.snappy) { self.photo = nil }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 22))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 6, y: -6)
                            .accessibilityLabel("Remove photo")
                        }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Photo attached").font(.mina(.subheadline, weight: .medium)).foregroundStyle(MinaTheme.text)
                        Text("Location and camera details are removed before it syncs.")
                            .font(.mina(.caption)).foregroundStyle(MinaTheme.textMuted)
                        Button("Replace") { choosing = true }
                            .font(.mina(.subheadline, weight: .semibold)).tint(tint)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Menu {
                    if cameraAvailable {
                        Button("Take photo", systemImage: "camera") { takingPhoto = true }
                    }
                    Button("Choose from library", systemImage: "photo.on.rectangle") { choosing = true }
                } label: {
                    Label(preparing ? "Adding photo…" : "Add photo", systemImage: "camera")
                        .font(.mina(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .tint(tint)
                .disabled(preparing)
                .accessibilityIdentifier("add-photo")
            }
        }
        .photosPicker(isPresented: $choosing, selection: $pickerItem, matching: .images, photoLibrary: .shared())
        .fullScreenCover(isPresented: $takingPhoto) {
            CameraPicker { image in
                if let image { prepare { PhotoStore.prepare(image) } }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $viewing) {
            if let photo { PhotoViewer(jpeg: photo.full) }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            preparing = true
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                let prepared = await Task.detached(priority: .userInitiated) { data.flatMap(PhotoStore.prepare(data:)) }.value
                withAnimation(.snappy) { photo = prepared ?? photo }
                preparing = false
            }
        }
    }

    /// Runs the resize off the main thread; a 12 MP camera frame takes a moment.
    private func prepare(_ work: @escaping @Sendable () -> EntryPhoto?) {
        preparing = true
        Task {
            let prepared = await Task.detached(priority: .userInitiated, operation: work).value
            withAnimation(.snappy) { photo = prepared ?? photo }
            preparing = false
        }
    }
}

// MARK: Camera

/// `UIImagePickerController` for the camera only; the library goes through
/// `PhotosPicker`, which needs no permission.
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.onFinish(info[.originalImage] as? UIImage)
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onFinish(nil)
            parent.dismiss()
        }
    }
}

// MARK: Row thumbnail

/// The 44 pt picture at the trailing edge of a row; tapping it opens the viewer
/// while the rest of the row still opens the editor.
struct EntryThumbnail: View {
    let thumb: Data
    /// Loaded only when the viewer opens, so a list never reads the full blob.
    let full: () -> Data?

    @State private var viewing = false

    var body: some View {
        Group {
            if let image = UIImage(data: thumb) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(MinaTheme.textMuted)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture { viewing = true }
        .accessibilityLabel("Photo")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("entry-photo")
        .fullScreenCover(isPresented: $viewing) {
            PhotoViewer(jpeg: full() ?? thumb)
        }
    }
}

// MARK: Viewer

/// The picture full screen: pinch to zoom, double-tap to reset, share the
/// JPEG, close.
struct PhotoViewer: View {
    let jpeg: Data

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var pinch: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var drag: CGSize = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image = UIImage(data: jpeg) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(zoom * pinch)
                        .offset(x: offset.width + drag.width, y: offset.height + drag.height)
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in pinch = value.magnification }
                                .onEnded { value in
                                    zoom = min(6, max(1, zoom * value.magnification))
                                    pinch = 1
                                    if zoom == 1 { withAnimation(.snappy) { offset = .zero } }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in if zoom > 1 { drag = value.translation } }
                                .onEnded { value in
                                    guard zoom > 1 else { drag = .zero; return }
                                    offset = CGSize(width: offset.width + value.translation.width, height: offset.height + value.translation.height)
                                    drag = .zero
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.snappy) {
                                zoom = zoom > 1 ? 1 : 2.5
                                offset = .zero
                            }
                        }
                        .accessibilityLabel("Photo")
                } else {
                    Text("This photo couldn't be opened.").foregroundStyle(.white)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: SharedPhoto(jpeg: jpeg), preview: SharePreview("Photo", image: Image(uiImage: UIImage(data: jpeg) ?? UIImage()))) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

/// The stored JPEG as something the share sheet can hand to Messages or Files.
struct SharedPhoto: Transferable {
    let jpeg: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { $0.jpeg }
            .suggestedFileName("Mina photo.jpg")
    }
}
