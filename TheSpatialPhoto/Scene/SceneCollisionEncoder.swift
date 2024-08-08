import Metal
import SimulationTools

final class SceneCollisionEncoder {
    private let backgroundQueue: DispatchQueue = .init(label: "Mesh Processing")
    private var triangleNeigbhors: MTLTypedBuffer?

    private let handleSceneCollision: MTLComputePipelineState
    private var triangles: MTLTypedBuffer?
    private var scenePositions: MTLTypedBuffer?
    private var triangleSpatialHashing: TriangleSpatialHashing?
    private var initialized = false

    init(device: MTLDevice) throws {
        handleSceneCollision = try device.makeDefaultLibrary(bundle: .main).computePipelineState(function: "handleVertexTriangleCollision")
    }
    
    func update(collider: SimpleGeometry, updateTriangleNeigbhors: Bool) throws {
        let cellSize: Float = 0.05
        let configuration = TriangleSpatialHashing.Configuration(cellSize: cellSize)
        triangleSpatialHashing = try .init(
            heap: device.heap(
                size: TriangleSpatialHashing.totalBuffersSize(maxTrianglesCount: collider.trianglesCount, configuration: configuration),
                storageMode: .private
            ),
            configuration: configuration,
            maxTrianglesCount: collider.trianglesCount
        )

        triangles = device.typedBuffer(with: collider.triangles, valueType: .packedUInt3)
        scenePositions = device.typedBuffer(with: collider.positions, valueType: .packedFloat3)
        
        if updateTriangleNeigbhors {
            backgroundQueue.async { [weak self] in
                if let indices = collider.triangles.array(of: UInt32.self, count: collider.trianglesCount * 3) {
                    let adjacentTriangles = findAdjacentTriangles(indices: indices)
                    self?.triangleNeigbhors = try? device.typedBuffer(with: adjacentTriangles, valueType: .uint3)
                }
            }
        }
        
        initialized = false
    }

    func build(
        commandBuffer: MTLCommandBuffer,
        positions: MTLTypedBuffer,
        collisionCandidates:  MTLTypedBuffer,
        vertexNeighbors: MTLTypedBuffer
    ) {
        guard let triangles = triangles, let scenePositions = scenePositions, let triangleSpatialHashing else { return }
        
        if !initialized {
            triangleSpatialHashing.build(
                colliderPositions: scenePositions,
                indices: triangles,
                in: commandBuffer
            )
        }
        
        triangleSpatialHashing.find(
            collidablePositions: positions,
            colliderPositions: scenePositions,
            indices: triangles,
            collisionCandidates: collisionCandidates,
            in: commandBuffer
        )
        
        initialized = true
    }
    
    func reuse(
        commandBuffer: MTLCommandBuffer,
        positions: MTLTypedBuffer,
        collisionCandidates:  MTLTypedBuffer,
        vertexNeighbors: MTLTypedBuffer
    ) {
        guard let triangles = triangles, let scenePositions = scenePositions, let triangleSpatialHashing else { return }

        triangleSpatialHashing.reuse(
            collidablePositions: positions,
            colliderPositions: scenePositions,
            indices: triangles,
            collisionCandidates: collisionCandidates,
            vertexNeighbors: vertexNeighbors,
            trinagleNeighbors: triangleNeigbhors,
            in: commandBuffer
        )
    }
    
    func encode(
        commandBuffer: MTLCommandBuffer,
        positions: MTLTypedBuffer,
        prevPositions: MTLTypedBuffer,
        collisionCandidates:  MTLTypedBuffer,
        frictionCoefficent: Float
    ) {
        guard let triangles = triangles, let scenePositions = scenePositions else { return }

        commandBuffer.compute { encoder in
            encoder.setBuffer(positions.buffer, offset: 0, index: 0)
            encoder.setBuffer(prevPositions.buffer, offset: 0, index: 1)
            encoder.setBuffer(collisionCandidates.buffer, offset: 0, index: 2)
            encoder.setBuffer(scenePositions.buffer, offset: 0, index: 3)
            encoder.setBuffer(triangles.buffer, offset: 0, index: 4)
            encoder.setValue(frictionCoefficent, at: 5)
            encoder.setValue(UInt32(collisionCandidates.descriptor.count / positions.descriptor.count), at: 6)
            encoder.setValue(UInt32(positions.descriptor.count), at: 7)

            encoder.dispatch1d(state: handleSceneCollision, exactlyOrCovering: positions.descriptor.count)
        }
    }
}


private func findAdjacentTriangles(indices: [UInt32]) -> [SIMD3<UInt32>] {
    let triangleCount = indices.count / 3
    var edgeToTriangle = [Set<UInt32>: Set<UInt32>]()
    
    for i in 0..<triangleCount {
        let i0 = (indices[i * 3])
        let i1 = (indices[i * 3 + 1])
        let i2 = (indices[i * 3 + 2])
        
        let edges = [
            Set([i0, i1]),
            Set([i1, i2]),
            Set([i2, i0])
        ]
        
        for edge in edges {
            edgeToTriangle[edge,default: Set<UInt32>()].insert(UInt32(i))
        }
    }
    
    var result = [SIMD3<UInt32>]()
    for i in 0..<triangleCount {
        let i0 = indices[i * 3]
        let i1 = indices[i * 3 + 1]
        let i2 = indices[i * 3 + 2]
        
        let edges = [
            Set([i0, i1]),
            Set([i1, i2]),
            Set([i2, i0])
        ]
        
        var adjacentTriangles = [UInt32](repeating: .max, count: 3)
        
        for (j, edge) in edges.enumerated() {
            let triangles = edgeToTriangle[edge, default: []]
            if triangles.count == 2 {
                adjacentTriangles[j] = triangles.subtracting([UInt32(i)]).first!
            }
        }
        
        result.append(SIMD3(adjacentTriangles[0], adjacentTriangles[1], adjacentTriangles[2]))
    }
    
    return result
}
