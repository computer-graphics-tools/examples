import RealityKit
import Metal

struct ParticlesUpdateComponent: Component {
    var particleMeshBuilder: ParticleMeshBuilder
}

struct ParticlesUpdateSystem: System {
    static let query = EntityQuery(where: .has(ParticlesUpdateComponent.self) && .has(SimulationComponent.self))
    
    init(scene: RealityKit.Scene) {
        ParticlesUpdateComponent.registerComponent()
    }
    
    func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard let meshComponent = entity.components[ParticlesUpdateComponent.self],
                  let simulationComponent = entity.components[SimulationComponent.self],
                  let commandBuffer = commandQueue.makeCommandBuffer()
            else { continue }
            
            
            if let simulator = simulationComponent.simulator {
                meshComponent.particleMeshBuilder.replaceMeshBuffer(
                    poisitionsBuffer: simulator.positions.buffer,
                    vertexNeighbors: simulator.selfCollisionCandidates.buffer,
                    commandBuffer: commandBuffer
                )
                
                commandBuffer.commit()
            }
        }
    }
}
