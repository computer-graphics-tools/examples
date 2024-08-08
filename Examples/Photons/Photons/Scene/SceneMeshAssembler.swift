import Metal
import ARKit

final class MeshAssembler {
    private let device: MTLDevice
    private let positionsPipelineState: MTLComputePipelineState
    private let indicesPipelineState: MTLComputePipelineState
    
    private var outputVertexBuffer: MTLBuffer?
    private var outputIndexBuffer: MTLBuffer?
    
    private(set) var totalVertexCount: Int = 0
    private(set) var totalIndexCount: Int = 0

    init(device: MTLDevice) throws {
        self.device = device

        let library = try device.makeDefaultLibrary(bundle: .main)
        positionsPipelineState = try library.computePipelineState(function: "assembleScenePositions")
        indicesPipelineState = try library.computePipelineState(function: "assembleSceneIndices")
    }

    func assembleMeshes(from geometries: [UUID: AnchorGeometry], completion: @escaping (SimpleGeometry) -> Void) {
        computeOutputBufferSizes(from: geometries)
        createOutputBufffers()
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        var vertexOffset: Int = 0
        var indexOffset: Int = 0

        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder(dispatchType: .concurrent) else { return }
        for geometry in geometries.values {
            encodePositionsKernel(computeEncoder: computeEncoder, geometry: geometry, vertexOffset: vertexOffset)
            encodeIndicesKernel(computeEncoder: computeEncoder, geometry: geometry, indexOffset: indexOffset, vertexOffset: UInt32(vertexOffset))

            vertexOffset += geometry.vertexCount
            indexOffset += geometry.faceCount * 3
        }
        
        computeEncoder.endEncoding()

        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self, let outputVertexBuffer, let outputIndexBuffer else { return }
            completion(
                .init(
                    positions: outputVertexBuffer,
                    triangles: outputIndexBuffer,
                    positionsCount: self.totalVertexCount,
                    trianglesCount: self.totalIndexCount / 3
                )
            )
        }
        commandBuffer.commit()
    }

    private func encodePositionsKernel(computeEncoder: MTLComputeCommandEncoder, geometry: AnchorGeometry, vertexOffset: Int) {
        computeEncoder.setBuffer(outputVertexBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(geometry.vertices.buffer, offset: 0, index: 1)

        computeEncoder.setValue(UInt32(geometry.vertexCount), at: 2)
        computeEncoder.setValue(UInt32(vertexOffset), at: 3)
        computeEncoder.setValue(geometry.transform, at: 4)

        computeEncoder.dispatch1d(state: positionsPipelineState, exactlyOrCovering: geometry.vertexCount)
    }

    private func encodeIndicesKernel(computeEncoder: MTLComputeCommandEncoder, geometry: AnchorGeometry, indexOffset: Int, vertexOffset: UInt32) {
        computeEncoder.setBuffer(outputIndexBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(geometry.faces.buffer, offset: 0, index: 1)

        computeEncoder.setValue(UInt32(geometry.faceCount * 3), at: 2)
        computeEncoder.setValue(UInt32(indexOffset), at: 3)
        computeEncoder.setValue(vertexOffset, at: 4)
        computeEncoder.setValue(geometry.transform, at: 5)

        computeEncoder.dispatch1d(state: indicesPipelineState, exactlyOrCovering: geometry.faceCount * 3)
    }

    private func computeOutputBufferSizes(from geometries: [UUID: AnchorGeometry]) {
        totalVertexCount = geometries.values.reduce(0) { $0 + $1.vertexCount }
        totalIndexCount = geometries.values.reduce(0) { $0 + $1.faceCount * 3 }
    }

    private func createOutputBufffers() {
        outputVertexBuffer = device.makeBuffer(length: MemoryLayout<Float>.size * 3 * totalVertexCount, options: [])
        outputIndexBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.size * totalIndexCount, options: [])
    }
}
