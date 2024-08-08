import RealityKit
import Metal

struct ParticleVertex {
    var position: SIMD4<Float16> = .zero
    var uv: SIMD2<Float> = .zero
    var uv2: SIMD2<Float> = .zero

}

extension ParticleVertex {
    static var vertexAttributes: [LowLevelMesh.Attribute] = [
        .init(semantic: .position, format: .half4, offset: MemoryLayout<Self>.offset(of: \.position)!),
        .init(semantic: .uv0, format: .float2, offset: MemoryLayout<Self>.offset(of: \.uv)!),
        .init(semantic: .uv1, format: .float2, offset: MemoryLayout<Self>.offset(of: \.uv2)!),
    ]
    
    static var vertexLayouts: [LowLevelMesh.Layout] = [
        .init(bufferIndex: 0, bufferStride: MemoryLayout<Self>.stride)
    ]
    
    static var descriptor: LowLevelMesh.Descriptor {
        var desc = LowLevelMesh.Descriptor()
        desc.vertexAttributes = ParticleVertex.vertexAttributes
        desc.vertexLayouts = ParticleVertex.vertexLayouts
        desc.indexType = .uint32
        return desc
    }
}

final class ParticleMeshBuilder {
    private var pipelineState: MTLComputePipelineState
    private let device: MTLDevice
    private var lowLevelMesh: LowLevelMesh?
    private var particlePositions: [SIMD4<Float>]
    private var uvs: [SIMD2<Float>]
    private var size: CGSize
    private var cellSize: Float
    private(set) var uvBuffer: MTLBuffer

    init(
        device: MTLDevice,
        positions: [SIMD4<Float>],
        uvs: [SIMD2<Float>],
        cellSize: Float,
        size: CGSize
    ) throws {
        let library = try device.makeDefaultLibrary(bundle: .main)
        self.device = device
        self.particlePositions = positions
        self.uvs = uvs
        self.size = size
        self.cellSize = cellSize
        uvBuffer = try device.buffer(with: uvs)
        pipelineState =  try library.computePipelineState(function: "updateVertexBuffer")
    }
    
    @MainActor func createMeshResource() throws -> MeshResource {
        let lowLevelMesh = try buildMesh()
        let resource = try MeshResource(from: lowLevelMesh)
        self.lowLevelMesh = lowLevelMesh
        return resource
    }
    
    @MainActor func replaceMeshBuffer(
        poisitionsBuffer: MTLBuffer,
        vertexNeighbors: MTLBuffer,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let lowLevelMesh else { return }
        let vertexBuffer = lowLevelMesh.replace(bufferIndex: 0, using: commandBuffer)
        let positionsCount = lowLevelMesh.vertexCapacity
    
        commandBuffer.compute { encoder in
            encoder.setBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setBuffer(poisitionsBuffer, offset: 0, index: 1)
            encoder.setValue(UInt32(positionsCount), at: 2)
            encoder.setBuffer(uvBuffer, offset: 0, index: 3)
            encoder.setValue(Float(size.height / size.width), at: 4)
            encoder.setValue(cellSize, at: 5)
            encoder.dispatch1d(state: pipelineState, exactlyOrCovering: positionsCount)
        }
    }
    
    @MainActor private func buildMesh() throws -> LowLevelMesh {
        let halfSize = cellSize / 2
        
        var positions: [SIMD4<Float>] = []
        var indices: [UInt32] = []

        for particlePosition in particlePositions {
            let particlePos = SIMD3<Float>(particlePosition.x, particlePosition.y, particlePosition.z)
            
            let quadVertices: [SIMD4<Float>] = [
                SIMD4<Float>(particlePos.x - halfSize, particlePos.y - halfSize, particlePos.z - halfSize, 1.0),
                SIMD4<Float>(particlePos.x + halfSize, particlePos.y - halfSize, particlePos.z - halfSize, 1.0),
                SIMD4<Float>(particlePos.x - halfSize, particlePos.y + halfSize, particlePos.z - halfSize, 1.0),
                SIMD4<Float>(particlePos.x + halfSize, particlePos.y + halfSize, particlePos.z - halfSize, 1.0),
            ]

            positions.append(contentsOf: quadVertices)
            let baseIndex = UInt32(positions.count - 4)
            let quadIndices: [UInt32] = (0..<1).flatMap { face -> [UInt32] in
                let faceBaseIndex = baseIndex + UInt32(face * 4)
                return [
                    faceBaseIndex, faceBaseIndex + 1, faceBaseIndex + 2,
                    faceBaseIndex + 1, faceBaseIndex + 3, faceBaseIndex + 2
                ]
            }
            indices.append(contentsOf: quadIndices)
        }
        
        var desciptor = ParticleVertex.descriptor
        desciptor.vertexCapacity = positions.count
        desciptor.indexCapacity = indices.count
        
        let lowMesh = try LowLevelMesh(descriptor: desciptor)
        lowMesh.withUnsafeMutableIndices { rawIndices in
            let targetIndices = rawIndices.bindMemory(to: UInt32.self)
            for i in 0..<desciptor.indexCapacity {
                targetIndices[i] = indices[i]
            }
        }
        
        let meshBounds = BoundingBox(min: [-100, -100, -100], max: [100, 100, 100])
        
        lowMesh.parts.replaceAll([
            LowLevelMesh.Part(
                indexCount: indices.count,
                topology: .triangle,
                bounds: meshBounds
            )
        ])

        return lowMesh
    }
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        .init(x: x, y: y, z: z)
    }
}
