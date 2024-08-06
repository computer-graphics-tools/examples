import SwiftUI
import _PhotosUI_SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {
    @EnvironmentObject private var viewModel: ViewModel
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        VStack {
            ZStack {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            viewModel.reset()
                        } label: {
                            Text("Reset")
                        }
                        .padding()
                    }
                    Spacer()
                }
                VStack {
                    Spacer()
                        HStack {
                            PhotosPicker(selection: $selectedItem, matching: .images,  photoLibrary: .shared()) {
                                Image(systemName: "square.and.arrow.down")
                            }
                            .onChange(of: selectedItem) { _, _ in
                                Task {
                                    if let data = try? await selectedItem?.loadTransferable(type: Data.self),
                                       let image = UIImage(data: data) {
                                        viewModel.setSelectedImage(image)
                                    }
                                }
                            }
                            ToggleImmersiveSpaceButton()
                            Toggle(isOn: $viewModel.settings.showWireframe) {
                                Image(systemName: "squareshape.split.3x3")
                            }
                            .toggleStyle(.button)
                        }
                    Spacer()
                    }.padding(.horizontal, 128)
            }
        }
        .padding()
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
        .environmentObject(ViewModel())
}

struct ProfileImage: Transferable {
    let image: Image
    
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
        #if canImport(AppKit)
            guard let nsImage = NSImage(data: data) else {
                throw TransferError.importFailed
            }
            let image = Image(nsImage: nsImage)
            return ProfileImage(image: image)
        #elseif canImport(UIKit)
            guard let uiImage = UIImage(data: data) else {
                throw NSError(domain: "failed to load", code: 293583)
            }
            let image = Image(uiImage: uiImage)
            return ProfileImage(image: image)
        #else
            throw TransferError.importFailed
        #endif
        }
    }
}
