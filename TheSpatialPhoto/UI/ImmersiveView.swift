import SwiftUI
import RealityKit
import RealityKitContent
import PhotosUI

struct ImmersiveView: View {
    private enum Constants {
        static let textureParamterName = "texture"
        static let timeParameterName = "time"
        static let cellSizeParamaterName = "cellSize"
    }
    
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var viewModel: ViewModel
    @State private var particlesEntity: Entity?
    private let session = SpatialTrackingSession()

    var body: some View {
        RealityView(make: { content in
#if !targetEnvironment(simulator)
            _ = await session.run(.init(tracking: [.hand]))
#endif
            let rootEntity = Entity()
            Task {
                var particleMaterial = try await ShaderGraphMaterial(named: "/Root/BillboardMaterial", from: "Immersive", in: realityKitContentBundle)
                try await configureParticleMaterial(material: &particleMaterial, startTime: CACurrentMediaTime())
                try updateParticlesModel(rootEntity: rootEntity, material: particleMaterial)
            }

            let leftPalm = AnchorEntity(.hand(.left, location: .palm))
            leftPalm.name = "LeftPalm"
            let rightPalm = AnchorEntity(.hand(.right, location: .palm))
            rightPalm.name = "RightPalm"
            let head = AnchorEntity(.head)
            head.name = "Head"
            rootEntity.addChild(leftPalm)
            rootEntity.addChild(rightPalm)
            rootEntity.addChild(head)
            
            #if !targetEnvironment(simulator)
            rootEntity.components[SceneMeshProviderComponent.self] = .init(meshBuilder: viewModel.sceneMeshBuilder)
            #endif
            rootEntity.components[SettingsComponent.self] = .init(settings: viewModel.settings)

            content.add(rootEntity)
            
            SimulationSystem.registerSystem()
            ParticlesUpdateSystem.registerSystem()
            #if !targetEnvironment(simulator)
            SceneUpdateSystem.registerSystem()
            #endif
        }, update: { content in
            let model = particlesEntity?.components[ModelComponent.self]
            particlesEntity?.components.set(OpacityComponent(opacity: 0.0))
            Task {
                if var material = model?.materials.first as? ShaderGraphMaterial, var model {
                    try? await self.configureParticleMaterial(material: &material, startTime: viewModel.settings.startTime)
                    model.materials = [material]
                    particlesEntity?.components[ModelComponent.self] = model
                    particlesEntity?.components.set(OpacityComponent(opacity: 1.0))
                    
                    if let simulatorComponent = particlesEntity?.components[SimulationComponent.self] {
                        if let rootEntity = particlesEntity?.parent, simulatorComponent.simulator == nil {
                            try updateParticlesModel(rootEntity: rootEntity, material: material)
                        }
                    }
                }
            }
        })
        .onChange(of: appModel.immersiveSpaceState) { _, _ in
            self.viewModel.settings.startTime = CACurrentMediaTime()
        }
    }
    
    private func updateParticlesModel(rootEntity: Entity, material: RealityKit.Material) throws {
        let meshResource = try viewModel.particleMeshBuilder.createMeshResource()
        let particlesEntity = ModelEntity(mesh: meshResource, materials: [material])
        particlesEntity.components[SimulationComponent.self] = .init(simulator: viewModel.simulator)
        particlesEntity.components[ParticlesUpdateComponent.self] = .init(
            ParticlesUpdateComponent(particleMeshBuilder: viewModel.particleMeshBuilder)
        )
        
        self.particlesEntity?.removeFromParent()
        rootEntity.addChild(particlesEntity)
        self.particlesEntity = particlesEntity
    }
    
    private func configureParticleMaterial(material: inout ShaderGraphMaterial, startTime: TimeInterval) async throws {
        let correctedImage = viewModel.selectedImage.correctlyOrientedImage()
        let texResource = try await TextureResource(image: correctedImage.cgImage!, options: .init(semantic: .color))
        try? material.setParameter(name: Constants.timeParameterName, value: .float(Float(startTime)))
        try? material.setParameter(name: Constants.textureParamterName, value: .textureResource(texResource))
        try? material.setParameter(name: Constants.cellSizeParamaterName, value: .float(Float(SimulationConstants.cellSize)))
    }
}


#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
        .environmentObject(ViewModel())
}
