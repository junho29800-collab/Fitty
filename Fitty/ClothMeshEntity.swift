import RealityKit
import simd
import UIKit

/// Packed vertex written into a `LowLevelMesh` buffer (iOS 18) or unpacked into
/// `MeshDescriptor` arrays (iOS 17). SIMD3 is 16-byte aligned so we store floats
/// explicitly and keep a 32-byte stride the GPU is happy with.
struct ClothVertex {
    var px, py, pz: Float
    var nx, ny, nz: Float
    var u, v: Float
}

/// RealityKit entity that displays the simulated garment with a physical PBR material.
///
/// Mesh strategy (verified against the iOS 17/18 SDKs):
/// * **iOS 18+** — `LowLevelMesh` + `MeshResource(from:)` (WWDC24 / RealityKit). Vertex
///   buffers are mutated in place via `withUnsafeMutableBytes` so a frame does not
///   allocate a new `MeshResource`. Indices are uploaded once.
/// * **iOS 17** — `MeshDescriptor` + `MeshResource.generate(from:)`. There is no
///   public mapped-buffer mesh on 17, so the resource is rebuilt on upload. That
///   path is correct but allocates; it exists so the project still deploys to 17.
///
/// Texture: `applyTexture(_:)` swaps `PhysicallyBasedMaterial.baseColor` on the
/// existing `ModelEntity`. UVs are u across columns, v down rows (shoulder → hip).
final class ClothMeshEntity: Entity {

    private let gridWidth: Int
    private let gridHeight: Int
    private let indexCount: Int

    private var model: ModelEntity
    private var pbr: PhysicallyBasedMaterial
    private var uv: [SIMD2<Float>]

    // iOS 18 path
    private var lowLevelMesh: AnyObject?
    private var indicesUploaded = false

    // iOS 17 scratch (preallocated; generate() still allocates the resource)
    private var positions17: [SIMD3<Float>]
    private var normals17: [SIMD3<Float>]
    private var indices32: [UInt32]

    init(width: Int, height: Int, indices: [UInt32]) {
        self.gridWidth = width
        self.gridHeight = height
        self.indexCount = indices.count
        self.indices32 = indices
        self.uv = []
        self.positions17 = Array(repeating: .zero, count: width * height)
        self.normals17 = Array(repeating: SIMD3<Float>(0, 0, 1), count: width * height)

        var material = PhysicallyBasedMaterial()
        // Cool woven cotton: mostly dielectric, mid roughness so folds read under
        // the directional light without turning into a mirror.
        material.baseColor = .init(tint: UIColor(red: 0.18, green: 0.38, blue: 0.78, alpha: 1))
        material.roughness = .init(floatLiteral: 0.50)
        material.metallic = .init(floatLiteral: 0.04)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.94))
        material.faceCulling = .none // garment is a thin sheet; both sides must render
        self.pbr = material

        let placeholder = MeshResource.generatePlane(width: 0.2, height: 0.3)
        self.model = ModelEntity(mesh: placeholder, materials: [material])
        super.init()
        name = "FittyCloth"
        addChild(model)

        uv.reserveCapacity(width * height)
        for row in 0..<height {
            for col in 0..<width {
                let u = width > 1 ? Float(col) / Float(width - 1) : 0
                let v = height > 1 ? Float(row) / Float(height - 1) : 0
                uv.append(SIMD2(u, v))
            }
        }

        if #available(iOS 18.0, *) {
            do {
                try setupLowLevelMesh(indexCount: indices.count)
            } catch {
                // Fall through to the MeshDescriptor path on the first upload.
            }
        }
    }

    @MainActor required init() {
        fatalError("ClothMeshEntity.init() is unused — call init(width:height:indices:)")
    }

    /// Map a scanned garment photo onto the existing cloth mesh. Does not allocate a
    /// new entity. `nil` restores the woven default tint. Alpha in a subject-lifted
    /// PNG drives opacity so the table background stays gone.
    func applyTexture(_ image: UIImage?) {
        pbr.roughness = .init(floatLiteral: 0.50)
        pbr.metallic = .init(floatLiteral: 0.04)
        pbr.faceCulling = .none

        if let image, let cg = image.cgImage {
            let options = TextureResource.CreateOptions(semantic: .color)
            do {
                let texture = try TextureResource.generate(from: cg,
                                                           withName: "fitty.garment.front",
                                                           options: options)
                let param = MaterialParameters.Texture(texture)
                pbr.baseColor = .init(texture: param, tint: .white)
                pbr.blending = .transparent(opacity: .init(scale: 1.0, texture: param))
            } catch {
                // Keep the previous material if the SDK rejects the CGImage.
            }
        } else {
            pbr.baseColor = .init(tint: UIColor(red: 0.18, green: 0.38, blue: 0.78, alpha: 1))
            pbr.blending = .transparent(opacity: .init(floatLiteral: 0.94))
        }

        if var modelComp = model.model {
            modelComp.materials = [pbr]
            model.model = modelComp
        }
    }

    @available(iOS 18.0, *)
    private func setupLowLevelMesh(indexCount: Int) throws {
        let vertexCount = gridWidth * gridHeight
        let stride = MemoryLayout<ClothVertex>.stride

        var desc = LowLevelMesh.Descriptor()
        desc.vertexCapacity = vertexCount
        desc.indexCapacity = indexCount
        desc.indexType = .uint32
        desc.vertexAttributes = [
            LowLevelMesh.Attribute(semantic: .position, format: .float3, offset: 0),
            LowLevelMesh.Attribute(semantic: .normal, format: .float3, offset: 12),
            LowLevelMesh.Attribute(semantic: .uv0, format: .float2, offset: 24)
        ]
        desc.vertexLayouts = [
            LowLevelMesh.Layout(bufferIndex: 0, bufferOffset: 0, bufferStride: stride)
        ]

        let mesh = try LowLevelMesh(descriptor: desc)
        let resource = try MeshResource(from: mesh)
        model.model = ModelComponent(mesh: resource, materials: [pbr])
        lowLevelMesh = mesh
    }

    /// Copy packed xyz positions/normals from the solver into the GPU mesh.
    /// Must run on the main/render thread — RealityKit is not thread-safe.
    func upload(positionsPacked: UnsafePointer<Float>,
                normalsPacked: UnsafePointer<Float>,
                particleCount: Int) {
        let count = min(particleCount, gridWidth * gridHeight)
        var minP = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maxP = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)

        if #available(iOS 18.0, *), let anyMesh = lowLevelMesh {
            uploadLowLevel(mesh: anyMesh,
                           positionsPacked: positionsPacked,
                           normalsPacked: normalsPacked,
                           count: count,
                           minP: &minP,
                           maxP: &maxP)
            return
        }
        uploadMeshDescriptor(positionsPacked: positionsPacked,
                             normalsPacked: normalsPacked,
                             count: count)
    }

    @available(iOS 18.0, *)
    private func uploadLowLevel(mesh anyMesh: AnyObject,
                                positionsPacked: UnsafePointer<Float>,
                                normalsPacked: UnsafePointer<Float>,
                                count: Int,
                                minP: inout SIMD3<Float>,
                                maxP: inout SIMD3<Float>) {
        guard let mesh = anyMesh as? LowLevelMesh else { return }

        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let verts = raw.bindMemory(to: ClothVertex.self)
            for i in 0..<count {
                let p = SIMD3<Float>(positionsPacked[i * 3 + 0],
                                     positionsPacked[i * 3 + 1],
                                     positionsPacked[i * 3 + 2])
                let n = SIMD3<Float>(normalsPacked[i * 3 + 0],
                                     normalsPacked[i * 3 + 1],
                                     normalsPacked[i * 3 + 2])
                let uv = self.uv[i]
                verts[i] = ClothVertex(px: p.x, py: p.y, pz: p.z,
                                       nx: n.x, ny: n.y, nz: n.z,
                                       u: uv.x, v: uv.y)
                minP = simd_min(minP, p)
                maxP = simd_max(maxP, p)
            }
        }

        if !indicesUploaded {
            let src = indices32
            mesh.withUnsafeMutableIndices { raw in
                let dst = raw.bindMemory(to: UInt32.self)
                for i in 0..<src.count {
                    dst[i] = src[i]
                }
            }
            indicesUploaded = true
        }

        let bounds = BoundingBox(min: minP, max: maxP)
        mesh.parts.replaceAll([
            LowLevelMesh.Part(indexCount: indexCount,
                              topology: .triangle,
                              bounds: bounds)
        ])
    }

    private func uploadMeshDescriptor(positionsPacked: UnsafePointer<Float>,
                                      normalsPacked: UnsafePointer<Float>,
                                      count: Int) {
        for i in 0..<count {
            positions17[i] = SIMD3(positionsPacked[i * 3 + 0],
                                   positionsPacked[i * 3 + 1],
                                   positionsPacked[i * 3 + 2])
            normals17[i] = SIMD3(normalsPacked[i * 3 + 0],
                                 normalsPacked[i * 3 + 1],
                                 normalsPacked[i * 3 + 2])
        }
        var descriptor = MeshDescriptor(name: "FittyCloth")
        descriptor.positions = MeshBuffers.Positions(positions17)
        descriptor.normals = MeshBuffers.Normals(normals17)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        descriptor.primitives = .triangles(indices32)
        do {
            let resource = try MeshResource.generate(from: [descriptor])
            model.model = ModelComponent(mesh: resource, materials: [pbr])
        } catch {
            // Keep the last good mesh if generate fails for a degenerate frame.
        }
    }
}
