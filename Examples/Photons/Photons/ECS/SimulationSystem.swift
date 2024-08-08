import RealityKit

struct SimulationComponent: Component {
    weak var simulator: Simulation?
}

struct SimulationSystem: System {
    static let query = EntityQuery(where: .has(SimulationComponent.self))
    
    init(scene: RealityKit.Scene) {
        SimulationComponent.registerComponent()
    }
    
    func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {            
            guard
                let simulationComponent = entity.components[SimulationComponent.self],
                let leftPalm = context.scene.findEntity(named: "LeftPalm") as? AnchorEntity,
                let rightPalm = context.scene.findEntity(named: "RightPalm") as? AnchorEntity,
                let head = context.scene.findEntity(named: "Head") as? AnchorEntity,
                let commandBuffer = commandQueue.makeCommandBuffer()
              else { continue }

            simulationComponent.simulator?.update(
                leftHandPosition: leftPalm.position(relativeTo: nil),
                rightHandPosition: rightPalm.position(relativeTo: nil),
                headPosition: head.position(relativeTo: nil),
                commandBuffer: commandBuffer,
                dt: context.deltaTime
            )
            
            commandBuffer.commit()            
        }
    }
}
