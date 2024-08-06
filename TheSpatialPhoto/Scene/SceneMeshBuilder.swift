import RealityKit

struct SimpleVertex {
    var position: (Float, Float, Float) = (0, 0, 0)
}

extension SimpleVertex {
    static var vertexAttributes: [LowLevelMesh.Attribute] = [
        .init(semantic: .position, format: .float3, offset: 0),
    ]
    
    static var vertexLayouts: [LowLevelMesh.Layout] = [
        .init(bufferIndex: 0, bufferStride: MemoryLayout<Self>.stride)
    ]
    
    static var descriptor: LowLevelMesh.Descriptor {
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexAttributes = SimpleVertex.vertexAttributes
        descriptor.vertexLayouts = SimpleVertex.vertexLayouts
        descriptor.indexType = .uint32

        return descriptor
    }
}

final class SceneMeshBuilder {
    enum Error: Swift.Error {
        case missingGeometry
        case bufferCreationFailed
    }

    private(set) var needsMeshUpdate = false
    private(set) var geometry: SimpleGeometry?
    private var lowLevelMesh: LowLevelMesh?
    
    func updateGeometry(geometry: SimpleGeometry) {
        self.geometry = geometry
        needsMeshUpdate = true
    }

    @MainActor func createMeshResource() throws -> MeshResource {
        let lowLevelMesh = try buildMesh()
        let resource = try MeshResource(from: lowLevelMesh)
        self.lowLevelMesh = lowLevelMesh
        needsMeshUpdate = false

        return resource
    }
    
    @MainActor func buildMesh() throws -> LowLevelMesh {
        guard let geometry else { throw Error.missingGeometry }
        var desc = SimpleVertex.descriptor
        desc.vertexCapacity = geometry.positionsCount
        desc.indexCapacity = geometry.trianglesCount * 3

        let lowMesh = try LowLevelMesh(descriptor: desc)
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { throw Error.bufferCreationFailed }
        
        let positionsBuffer = lowMesh.replace(bufferIndex: 0, using: commandBuffer)
        let indicesBuffer = lowMesh.replaceIndices(using: commandBuffer)
        commandBuffer.blit { encoder in
            encoder.copy(from: geometry.positions, sourceOffset: 0, to: positionsBuffer, destinationOffset: 0, size: geometry.positions.length)
            encoder.copy(from: geometry.triangles, sourceOffset: 0, to: indicesBuffer, destinationOffset: 0, size: geometry.triangles.length)
        }
        commandBuffer.commit()
        let meshBounds = BoundingBox(min: [-100, -100, -100], max: [100, 100, 100])
        lowMesh.parts.replaceAll([
            LowLevelMesh.Part(
                indexCount: geometry.trianglesCount * 3,
                topology: .triangle,
                bounds: meshBounds
            )
        ])

        return lowMesh
    }
}

