import ARKit
import SimulationTools
import MetalTools
import simd

struct SimulationConstants {
    static let gravity: SIMD3<Float> = [0, -9.8, 0]
    static let particleRadius: Float = 0.025 / 2
    static var cellSize: Float { particleRadius * 2.0 }
    static let maxCollisionCandidates = 8
    static let solverIterations = 1
}

class Simulation {
    let device: MTLDevice
    
    private let predictPositionsPipelineState: MTLComputePipelineState
    private let solveConstraintsPipelineState: MTLComputePipelineState

    private let spatialHashing: SpatialHashing
    private let sceneCollisionEngine: SceneCollisionEncoder

    let positions: MTLTypedBuffer
    let selfCollisionCandidates: MTLTypedBuffer
    private let originalPositions: MTLTypedBuffer
    private let prevPositions: MTLTypedBuffer
    private let predictedPositions: MTLTypedBuffer
    private let collisionCandidates: MTLTypedBuffer
    
    private var time: Float = 0
    private var frame: Int = 0

    init(device: MTLDevice, positions: [SIMD4<Float>]) throws {
        self.device = device
        
        self.positions = try device.typedBuffer(with: positions, valueType: .float4)
        originalPositions = try device.typedBuffer(with: positions, valueType: .float4)
        prevPositions = try device.typedBuffer(with: positions, valueType: .float4)
        predictedPositions = try device.typedBuffer(with: positions, valueType: .float4)
        selfCollisionCandidates = try device.typedBuffer(descriptor: .init(valueType: .uint, count: positions.count * SimulationConstants.maxCollisionCandidates))
        collisionCandidates = try device.typedBuffer(descriptor: .init(valueType: .uint,count: positions.count * SimulationConstants.maxCollisionCandidates))
        
        let library = try device.makeDefaultLibrary(bundle: .main)
        predictPositionsPipelineState = try library.computePipelineState(function: "predictPositions")
        solveConstraintsPipelineState = try library.computePipelineState(function: "solveConstraints")

        let config = SpatialHashing.Configuration(cellSize: SimulationConstants.cellSize, radius: SimulationConstants.particleRadius)
        sceneCollisionEngine = try SceneCollisionEncoder(device: device)
        spatialHashing = try SpatialHashing(
            heap: device.heap(size: SpatialHashing.totalBuffersSize(maxPositionsCount: positions.count), storageMode: .private),
            configuration: config,
            maxPositionsCount: positions.count
        )
    }
    
    func updateScene(sceneGeometry: SimpleGeometry, event: AnchorUpdate<MeshAnchor>.Event) {
        try? sceneCollisionEngine.update(
            collider: sceneGeometry,
            updateTriangleNeigbhors: event != .updated
        )
    }
    
    func reset() {
        time = 0
        frame = 0
    }
    
    func update(
        leftHandPosition: SIMD3<Float>,
        rightHandPosition: SIMD3<Float>,
        headPosition: SIMD3<Float>,
        commandBuffer: MTLCommandBuffer,
        dt: TimeInterval
    ) {
        
        if frame == 0 && time == 0 {
            commandBuffer.blit { encoder in
                encoder.copy(from: originalPositions.buffer, sourceOffset: 0, to: positions.buffer, destinationOffset: 0, size: positions.buffer.length)
                encoder.copy(from: originalPositions.buffer, sourceOffset: 0, to: prevPositions.buffer, destinationOffset: 0, size: positions.buffer.length)
                encoder.copy(from: originalPositions.buffer, sourceOffset: 0, to: predictedPositions.buffer, destinationOffset: 0, size: positions.buffer.length)

            }
        }

        frame += 1
        let dt = 1.0 / 90
        time += Float(dt)
        for _ in 0..<SimulationConstants.solverIterations {
            if frame > 120 {
                commandBuffer.compute { predictEncoder in
                    predictEncoder.setBuffer(positions.buffer, offset: 0, index: 0)
                    predictEncoder.setBuffer(prevPositions.buffer, offset: 0, index: 1)
                    predictEncoder.setBuffer(predictedPositions.buffer, offset: 0, index: 2)
                    predictEncoder.setValue(SIMD3<Float>(0, -10, 0.0), at: 3)
                    predictEncoder.setValue(Float(dt), at: 4)
                    predictEncoder.setValue(UInt32(positions.descriptor.count), at: 5)
                    predictEncoder.setValue(leftHandPosition, at: 6)
                    predictEncoder.setValue(rightHandPosition, at: 7)
                    predictEncoder.setValue(headPosition, at: 8)
                    predictEncoder.dispatch1d(state: predictPositionsPipelineState, exactlyOrCovering: positions.descriptor.count)
                }
            }
            
            spatialHashing.build(
                positions: predictedPositions,
                in: commandBuffer
            )
            
            spatialHashing.find(
                collidablePositions: nil,
                collisionCandidates: selfCollisionCandidates,
                connectedVertices: nil,
                in: commandBuffer
            )  
            
            sceneCollisionEngine.build(
                commandBuffer: commandBuffer,
                positions: predictedPositions,
                collisionCandidates: collisionCandidates,
                vertexNeighbors: selfCollisionCandidates
            )
            
            sceneCollisionEngine.reuse(
                commandBuffer: commandBuffer,
                positions: predictedPositions,
                collisionCandidates: collisionCandidates,
                vertexNeighbors: selfCollisionCandidates
            )
            
            for j in 0..<3 {
                let source = j % 2 == 0 ? predictedPositions : positions
                let target = j % 2 == 0 ? positions : predictedPositions
                
                commandBuffer.compute { solveEncoder in
                    solveEncoder.setValue(leftHandPosition, at: 0)
                    solveEncoder.setValue(rightHandPosition, at: 1)
                    solveEncoder.setBuffer(selfCollisionCandidates.buffer, offset: 0, index: 2)
                    solveEncoder.setBuffer(source.buffer, offset: 0, index: 3)
                    solveEncoder.setBuffer(prevPositions.buffer, offset: 0, index: 4)
                    solveEncoder.setValue(SimulationConstants.maxCollisionCandidates, at: 5)
                    solveEncoder.setValue(SimulationConstants.particleRadius, at: 9)
                    solveEncoder.setBuffer(target.buffer, offset: 0, index: 10)
                    solveEncoder.setValue(UInt32(positions.descriptor.count), at: 11)
                    
                    solveEncoder.dispatch1d(state: solveConstraintsPipelineState, exactlyOrCovering: positions.descriptor.count)
                }
                
                sceneCollisionEngine.encode(
                    commandBuffer: commandBuffer,
                    positions: target,
                    prevPositions: prevPositions,
                    collisionCandidates: collisionCandidates,
                    frictionCoefficent: 0.5
                )
            }
        }
    }
}
