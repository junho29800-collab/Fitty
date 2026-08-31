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
/// Front + back: RealityKit PhysicallyBasedMaterial cannot bind a different texture
/// to back faces of a single material (`faceCulling = .none` samples the same UV).
/// When a back photo exists we:
///   1. Pack an atlas in U (left = front, right = back).
///   2. Duplicate the triangle list with reversed winding and UV.u += 0.5.
///   3. Set `faceCulling = .back` so each side samples its half.
/// Documented choice: atlas-in-U + split grid, not two-sided PBR.
final class ClothMeshEntity: Entity {

    private var gridWidth: Int
    private var gridHeight: Int
    private var indexCount: Int

    private var model: ModelEntity
    private var pbr: PhysicallyBasedMaterial
    private var uv: [SIMD2<Float>]

    private var lowLevelMesh: AnyObject?
    private var indicesUploaded = false
    private var atlasMode = false

    private var positions17: [SIMD3<Float>]
    private var normals17: [SIMD3<Float>]
    private var indices32: [UInt32]
    private var frontIndices: [UInt32]
    private var atlasIndices: [UInt32]

    init(width: Int, height: Int, indices: [UInt32]) {
        self.gridWidth = width
        self.gridHeight = height
        self.frontIndices = indices
        self.atlasIndices = ClothMeshEntity.makeAtlasIndices(front: indices, vertexCount: width * height)
        self.indices32 = indices
        self.indexCount = indices.count
        self.uv = []
        let cap = width * height * 2
        self.positions17 = Array(repeating: .zero, count: cap)
        self.normals17 = Array(repeating: SIMD3<Float>(0, 0, 1), count: cap)

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.18, green: 0.38, blue: 0.78, alpha: 1))
        material.roughness = .init(floatLiteral: 0.50)
        material.metallic = .init(floatLiteral: 0.04)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.94))
        material.faceCulling = .none
        self.pbr = material

        let placeholder = MeshResource.generatePlane(width: 0.2, height: 0.3)
        self.model = ModelEntity(mesh: placeholder, materials: [material])
        super.init()
        name = "FittyCloth"
        addChild(model)

        rebuildUVs(atlas: false)

        if #available(iOS 18.0, *) {
            do {
                try setupLowLevelMesh(vertexCapacity: cap, indexCount: atlasIndices.count)
            } catch {
            }
        }
    }

    @MainActor required init() {
        fatalError("ClothMeshEntity.init() is unused — call init(width:height:indices:)")
    }

    private static func makeAtlasIndices(front: [UInt32], vertexCount: Int) -> [UInt32] {
        var out = front
        out.reserveCapacity(front.count * 2)
        let off = UInt32(vertexCount)
        var i = 0
        while i + 2 < front.count {
            let a = front[i] + off
            let b = front[i + 1] + off
            let c = front[i + 2] + off
            out.append(a)
            out.append(c) // reverse winding so the back copy faces the other way
            out.append(b)
            i += 3
        }
        return out
    }

    private func rebuildUVs(atlas: Bool) {
        uv.removeAll(keepingCapacity: true)
        let n = gridWidth * gridHeight
        uv.reserveCapacity(n * 2)
        for row in 0..<gridHeight {
            for col in 0..<gridWidth {
                let u = gridWidth > 1 ? Float(col) / Float(gridWidth - 1) : 0
                let v = gridHeight > 1 ? Float(row) / Float(gridHeight - 1) : 0
                if atlas {
                    uv.append(SIMD2(u * 0.5, v))
                } else {
                    uv.append(SIMD2(u, v))
                }
            }
        }
        if atlas {
            for row in 0..<gridHeight {
                for col in 0..<gridWidth {
                    let u = gridWidth > 1 ? Float(col) / Float(gridWidth - 1) : 0
                    let v = gridHeight > 1 ? Float(row) / Float(gridHeight - 1) : 0
                    uv.append(SIMD2(0.5 + u * 0.5, v))
                }
            }
        }
    }

    /// Map a scanned garment onto the existing cloth mesh. Does not allocate a new entity.
    /// `nil` front restores the woven default tint.
    func applyTexture(front: UIImage?,
                      back: UIImage? = nil,
                      roughness: Float = 0.50,
                      metallic: Float = 0.04,
                      emissive: Float = 0) {
        pbr.roughness = .init(floatLiteral: roughness)
        pbr.metallic = .init(floatLiteral: metallic)
        let emit = max(0, min(emissive, 0.25))
        pbr.emissiveColor = .init(color: UIColor(white: CGFloat(emit), alpha: 1))

        let wantAtlas = (front != nil && back != nil)
        if wantAtlas != atlasMode {
            atlasMode = wantAtlas
            rebuildUVs(atlas: atlasMode)
            indices32 = atlasMode ? atlasIndices : frontIndices
            indexCount = indices32.count
            indicesUploaded = false
        }
        pbr.faceCulling = atlasMode ? .back : .none

        var source: UIImage? = front
        if let front, let back {
            source = ImageIOSupport.atlas(front: front, back: back) ?? front
        }

        if let image = source, let cg = image.cgImage {
            let options = TextureResource.CreateOptions(semantic: .color)
            do {
                let texture = try TextureResource.generate(from: cg,
                                                           withName: "fitty.garment.albedo",
                                                           options: options)
                let param = MaterialParameters.Texture(texture)
                pbr.baseColor = .init(texture: param, tint: .white)
                pbr.blending = .transparent(opacity: .init(scale: 1.0, texture: param))
            } catch {
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

    func setEmissive(_ value: Float) {
        let emit = max(0, min(value, 0.25))
        pbr.emissiveColor = .init(color: UIColor(white: CGFloat(emit), alpha: 1))
        if var modelComp = model.model {
            modelComp.materials = [pbr]
            model.model = modelComp
        }
    }

    @available(iOS 18.0, *)
    private func setupLowLevelMesh(vertexCapacity: Int, indexCount: Int) throws {
        let stride = MemoryLayout<ClothVertex>.stride
        var desc = LowLevelMesh.Descriptor()
        desc.vertexCapacity = vertexCapacity
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
        let copies = atlasMode ? 2 : 1

        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let verts = raw.bindMemory(to: ClothVertex.self)
            for copy in 0..<copies {
                let base = copy * count
                let flip = copy == 1
                for i in 0..<count {
                    let p = SIMD3<Float>(positionsPacked[i * 3 + 0],
                                         positionsPacked[i * 3 + 1],
                                         positionsPacked[i * 3 + 2])
                    var n = SIMD3<Float>(normalsPacked[i * 3 + 0],
                                         normalsPacked[i * 3 + 1],
                                         normalsPacked[i * 3 + 2])
                    if flip { n = -n }
                    let uvIndex = min(base + i, uv.count - 1)
                    let uv = self.uv[uvIndex]
                    verts[base + i] = ClothVertex(px: p.x, py: p.y, pz: p.z,
                                                  nx: n.x, ny: n.y, nz: n.z,
                                                  u: uv.x, v: uv.y)
                    minP = simd_min(minP, p)
                    maxP = simd_max(maxP, p)
                }
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
        let copies = atlasMode ? 2 : 1
        for copy in 0..<copies {
            let base = copy * count
            let flip = copy == 1
            for i in 0..<count {
                positions17[base + i] = SIMD3(positionsPacked[i * 3 + 0],
                                              positionsPacked[i * 3 + 1],
                                              positionsPacked[i * 3 + 2])
                var n = SIMD3<Float>(normalsPacked[i * 3 + 0],
                                     normalsPacked[i * 3 + 1],
                                     normalsPacked[i * 3 + 2])
                if flip { n = -n }
                normals17[base + i] = n
            }
        }
        let used = copies * count
        var descriptor = MeshDescriptor(name: "FittyCloth")
        descriptor.positions = MeshBuffers.Positions(Array(positions17.prefix(used)))
        descriptor.normals = MeshBuffers.Normals(Array(normals17.prefix(used)))
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(Array(uv.prefix(used)))
        descriptor.primitives = .triangles(indices32)
        do {
            let resource = try MeshResource.generate(from: [descriptor])
            model.model = ModelComponent(mesh: resource, materials: [pbr])
        } catch {
        }
    }
}
