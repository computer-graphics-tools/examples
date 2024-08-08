import RealityKit
import SwiftUI

struct SceneMeshProviderComponent: Component {
    var meshBuilder: SceneMeshBuilder
}

#if !targetEnvironment(simulator)
struct SceneUpdateSystem: System {
    static let query = EntityQuery(
        where: .has(SceneMeshProviderComponent.self) && .has(SettingsComponent.self)
    )

    init(scene: RealityKit.Scene) {
        SceneMeshProviderComponent.registerComponent()
    }
    
    func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard let providerComponent = entity.components[SceneMeshProviderComponent.self],
                  let settingsComponent = entity.components[SettingsComponent.self]
            else {
                continue
            }

            if let entity = entity.findEntity(named: "SceneDebugEntity") {
                entity.components.set(OpacityComponent(opacity: settingsComponent.settings.showWireframe ? 1.0 : 0.0))
            }

            if providerComponent.meshBuilder.needsMeshUpdate, let resource = try? providerComponent.meshBuilder.createMeshResource() {
                updateSceneMeshEntities(entity: entity, meshResource: resource)
            }
            
            entity.components[SceneMeshProviderComponent.self] = providerComponent
        }
    }
    
    private func updateSceneMeshEntities(entity: Entity, meshResource: MeshResource) {
        let occlusionMaterial = OcclusionMaterial()
        var lineMaterial = SimpleMaterial()
        lineMaterial.triangleFillMode = .lines

        for i in 0..<2 {
            let entityName = i == 0 ? "SceneEntity" : "SceneDebugEntity"
            let material: RealityKit.Material = i == 0 ? occlusionMaterial : lineMaterial
            
            if let existingEntity = entity.findEntity(named: entityName) {
                existingEntity.components.set(ModelComponent(mesh: meshResource, materials: [material]))
            } else {
                let newEntity = ModelEntity(mesh: meshResource, materials: [material])
                newEntity.name = entityName
                entity.addChild(newEntity)
            }
        }
    }
}
#endif
