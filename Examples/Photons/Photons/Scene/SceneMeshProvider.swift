import Metal
import ARKit
import RealityKit

public struct SimpleGeometry {
    let positions: MTLBuffer
    let triangles: MTLBuffer
    let positionsCount: Int
    let trianglesCount: Int
    
    init(positions: MTLBuffer, triangles: MTLBuffer, positionsCount: Int, trianglesCount: Int) {
        self.positions = positions
        self.triangles = triangles
        self.positionsCount = positionsCount
        self.trianglesCount = trianglesCount
    }
}

struct AnchorGeometry {
    let vertices: GeometrySource
    let faces: GeometryElement
    var transform: simd_float4x4
    let vertexCount: Int
    let faceCount: Int
}

final class SceneMeshProvider {
    private let session = ARKitSession()
    private let sceneReconstruction = SceneReconstructionProvider()
    private var anchorGeometries: [UUID: AnchorGeometry] = [:]
    private var cancellable: Task<Void, Error>?
    private let assembler: MeshAssembler

    var onMeshUpdate: ((SimpleGeometry, AnchorUpdate<MeshAnchor>.Event) -> Void)?
    var started: Bool = false

    init(device: MTLDevice) throws {
        assembler = try MeshAssembler(device: device)
#if !targetEnvironment(simulator)
        setupARSession()
#endif
    }
    
    func forceUpdate() {
#if !targetEnvironment(simulator)
        guard started else { return }
        guard !sceneReconstruction.allAnchors.isEmpty else { return }
        sceneReconstruction.allAnchors.forEach { achor in
            updateAnchorGeometry(achor)
        }

        assembler.assembleMeshes(from: anchorGeometries) { [weak self] collider in
            self?.onMeshUpdate?(collider, .added)
        }
#endif
    }
    
    private func setupARSession() {
        Task {
            do {
                try await session.run([sceneReconstruction])
                subscribeToContinuousUpdates()
                started = true
            } catch {
                print("Failed to run session: \(error)")
            }
        }
    }
    
    private func subscribeToContinuousUpdates() {
        cancellable = Task {
            for await update in sceneReconstruction.anchorUpdates {
                await handleAnchorUpdate(update)
            }
        }
    }
    
    private func handleAnchorUpdate(_ update: AnchorUpdateSequence<MeshAnchor>.Iterator<MeshAnchor>.Element) async {
        switch update.event {
        case .added:
            updateAnchorGeometry(update.anchor)
        case .updated:
            anchorGeometries[update.anchor.id]?.transform = update.anchor.originFromAnchorTransform
        case .removed:
            removeAnchorGeometry(update.anchor.id)

        }
        
        assembler.assembleMeshes(from: anchorGeometries) { [weak self] collider in
            guard let self else { return }
            self.onMeshUpdate?(collider, update.event)
        }
    }
    
    private func updateAnchorGeometry(_ anchor: MeshAnchor) {
        let geometry = anchor.geometry
        let transform = anchor.originFromAnchorTransform
        
        let anchorGeometry = AnchorGeometry(
            vertices: geometry.vertices,
            faces: geometry.faces,
            transform: transform,
            vertexCount: geometry.vertices.count,
            faceCount: geometry.faces.count
        )
        
        anchorGeometries[anchor.id] = anchorGeometry
    }
    
    private func removeAnchorGeometry(_ anchorID: UUID) {
        anchorGeometries.removeValue(forKey: anchorID)
    }
    
    deinit {
        cancellable?.cancel()
    }
}
