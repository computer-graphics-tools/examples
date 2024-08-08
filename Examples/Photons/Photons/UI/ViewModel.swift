import SwiftUI

final class ViewModel: ObservableObject {
    @Published var selectedImage: UIImage {
        didSet {
            let correctedImage = selectedImage.correctlyOrientedImage()
            let (particles, uvs) = Self.buildParticles(for: correctedImage)
            do {
                particleMeshBuilder = try .init(
                    device: device,
                    positions: particles,
                    uvs: uvs,
                    cellSize: SimulationConstants.cellSize,
                    size: correctedImage.size
                )
                simulator = try Simulation(device: device, positions: particles)
                settings.startTime = CACurrentMediaTime()
            } catch {
                fatalError("initialization failed")
            }
        }
    }

    @Published var settings = Settings()

    var particleMeshBuilder: ParticleMeshBuilder
    var sceneMeshBuilder: SceneMeshBuilder
    var simulator: Simulation
    let sceneMeshProvider: SceneMeshProvider
    
    init() {
        sceneMeshBuilder = SceneMeshBuilder()
        let image = UIImage(named: "hello_particles")!
        selectedImage = image
        let correctedImage =  image.correctlyOrientedImage()
        let (particles, uvs) = Self.buildParticles(for: correctedImage)
        do {
            sceneMeshProvider = try SceneMeshProvider(device: device)
            particleMeshBuilder = try ParticleMeshBuilder(
                device: device,
                positions: particles,
                uvs: uvs,
                cellSize: SimulationConstants.cellSize,
                size: image.size
            )
            simulator = try Simulation(device: device, positions: particles)
        } catch {
            fatalError("initialization failed")
        }
        
        settings.startTime = CACurrentMediaTime()
        sceneMeshProvider.onMeshUpdate = { geometry, event in
            DispatchQueue.main.async { [weak self] in
                self?.simulator.updateScene(sceneGeometry: geometry, event: event)
                Task {
                    self?.sceneMeshBuilder.updateGeometry(geometry: geometry)
                }
            }
        }
    }

    
    func setSelectedImage(_ image: UIImage) {
        selectedImage = image
    }
    
    func reset() {
        sceneMeshProvider.forceUpdate()
        simulator.reset()
        settings.startTime = CACurrentMediaTime()
        objectWillChange.send()
    }
}

extension ViewModel {
    private static func buildParticles(for image: UIImage) -> ([SIMD4<Float>], [SIMD2<Float>]) {
        let fixedHeight = 40
        let aspectRatio = Float(image.size.width / image.size.height)
        let width = Int(ceil(Float(fixedHeight) * aspectRatio))
        let depth = 11
        
        let count = width * fixedHeight * depth
        var positions = [SIMD4<Float>](repeating: .zero, count: count)
        var uvs = [SIMD2<Float>](repeating: .zero, count: count)
        
        let boxSize: SIMD3<Float> = [aspectRatio, 1.0, 1.0]
        let cellSizeX = 1.0 / Float(width)
        let cellSizeY = 1.0 / Float(fixedHeight)
        
        for x in 0..<width {
            for y in 0..<fixedHeight {
                for z in 0..<depth {
                    let index = (x * fixedHeight + y) * depth + z
                    let u = Float(x) / Float(width)
                    let v = Float(y) / Float(fixedHeight)
                    
                    let xPos = u * boxSize.x - boxSize.x / 2
                    let yPos = v * boxSize.y - boxSize.y / 2 + 1.5
                    let zPos = Float(z) * cellSizeY * boxSize.z - boxSize.z / 2 - 1.25
                    
                    let position = SIMD4<Float>(xPos, yPos, zPos, 1)
                    let uv = SIMD2<Float>(u + cellSizeX * 0.5, v + cellSizeY * 0.5)
                    
                    positions[index] = position
                    uvs[index] = uv
                }
            }
        }
        
        return (positions, uvs)
    }
}

final class Settings: Observable {
    var showWireframe = false
    var startTime: TimeInterval = CACurrentMediaTime()
}

extension UIImage {
    func correctlyOrientedImage() -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return normalizedImage
    }
}
