//
//  MeshHelpers.swift
//  scanUrBuddy
//
//  Created by Quentin Reiser on 9/5/21.
//  Copyright © 2021 Metal by Example. All rights reserved.
//

import Foundation
import UIKit
import ARKit

extension ScanViewController {
    
    func getTextureImage(frame: ARFrame) -> UIImage? {

        let pixelBuffer = frame.capturedImage
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        
        let context = CIContext(options:nil)
        guard let cameraImage = context.createCGImage(image, from: image.extent) else {return nil}

        return UIImage(cgImage: cameraImage)
    }


    func vertex(at index: UInt32, vertices: ARGeometrySource) -> SIMD3<Float> {
        assert(vertices.format == MTLVertexFormat.float3, "Expected three floats (twelve bytes) per vertex.")
        let vertexPointer = vertices.buffer.contents().advanced(by: vertices.offset + (vertices.stride * Int(index)))
        let vertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
        return vertex
    }

    func normal(at index: UInt32, normals: ARGeometrySource) -> SIMD3<Float> {
        assert(normals.format == MTLVertexFormat.float3, "Expected three floats (twelve bytes) per normal.")
        let normalPointer = normals.buffer.contents().advanced(by: normals.offset + (normals.stride * Int(index)))
        let normal = normalPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
        return normal
    }

    func face(at index: Int, faces: ARGeometryElement) -> [Int] {
        let indicesPerFace = faces.indexCountPerPrimitive
        let facesPointer = faces.buffer.contents()
        var vertexIndices = [Int]()
        for offset in 0..<indicesPerFace {
            let vertexIndexAddress = facesPointer.advanced(by: (index * indicesPerFace + offset) * MemoryLayout<UInt32>.size)
            vertexIndices.append(Int(vertexIndexAddress.assumingMemoryBound(to: UInt32.self).pointee))
        }
        return vertexIndices
    }

    func lineBetweenNodes(positionA: SCNVector3, positionB: SCNVector3, inScene: SCNScene) -> SCNNode {
        let vector = SCNVector3(positionA.x - positionB.x, positionA.y - positionB.y, positionA.z - positionB.z)
        let distance = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
        let mid = SCNVector3(x:(positionA.x + positionB.x) / 2, y:(positionA.y + positionB.y) / 2, z:(positionA.z + positionB.z) / 2)
        let quarter = SCNVector3(x:(positionA.x + mid.x) / 2, y:(positionA.y + mid.y) / 2, z:(positionA.z + mid.z) / 2)

        let lineGeometry = SCNCylinder()
        lineGeometry.radius = 0.001
        lineGeometry.height = CGFloat(distance / 2)
        lineGeometry.radialSegmentCount = 5
        lineGeometry.firstMaterial!.diffuse.contents = UIColor.magenta

        let lineNode = SCNNode(geometry: lineGeometry)
        lineNode.position = quarter
        lineNode.look (at: mid, up: inScene.rootNode.worldUp, localFront: lineNode.worldUp)
        lineNode.opacity = 0.6
        return lineNode
    }
}


extension ARMeshGeometry {
    func vertex(at index: UInt32) -> SIMD3<Float> {
        assert(vertices.format == MTLVertexFormat.float3, "Expected three floats (twelve bytes) per vertex.")
        let vertexPointer = vertices.buffer.contents().advanced(by: vertices.offset + (vertices.stride * Int(index)))
        let vertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
        return vertex
    }
    
    func normal(at index: UInt32) -> SIMD3<Float> {
        assert(normals.format == MTLVertexFormat.float3, "Expected three floats (twelve bytes) per normal.")
        let normalPointer = normals.buffer.contents().advanced(by: normals.offset + (normals.stride * Int(index)))
        let normal = normalPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
        return normal
    }
    
    func vertexIndicesOf(faceWithIndex index: Int) -> [Int] {
        let indicesPerFace = faces.indexCountPerPrimitive
        let facesPointer = faces.buffer.contents()
        var vertexIndices = [Int]()
        for offset in 0..<indicesPerFace {
            let vertexIndexAddress = facesPointer.advanced(by: (index * indicesPerFace + offset) * MemoryLayout<UInt32>.size)
            vertexIndices.append(Int(vertexIndexAddress.assumingMemoryBound(to: UInt32.self).pointee))
        }
        return vertexIndices
    }
}

extension  SCNGeometrySource {
    convenience init(_ source: ARGeometrySource, semantic: Semantic) {
           self.init(buffer: source.buffer, vertexFormat: source.format, semantic: semantic, vertexCount: source.count, dataOffset: source.offset, dataStride: source.stride)
    }
    
    convenience init(textureCoordinates texcoord: [vector_float2]) {
        let stride = MemoryLayout<vector_float2>.stride
        let bytePerComponent = MemoryLayout<Float>.stride
        let data = Data(bytes: texcoord, count: stride * texcoord.count)
        self.init(data: data, semantic: SCNGeometrySource.Semantic.texcoord, vectorCount: texcoord.count, usesFloatComponents: true, componentsPerVector: 2, bytesPerComponent: bytePerComponent, dataOffset: 0, dataStride: stride)
    }
}
extension  SCNGeometryElement {
    convenience init(_ source: ARGeometryElement) {
        let pointer = source.buffer.contents()
        let byteCount = source.count * source.indexCountPerPrimitive * source.bytesPerIndex
        let data = Data(bytesNoCopy: pointer, count: byteCount, deallocator: .none)
        self.init(data: data, primitiveType: .of(source.primitiveType), primitiveCount: source.count, bytesPerIndex: source.bytesPerIndex)
    }
}

extension  SCNGeometryPrimitiveType {
    static  func  of(_ type: ARGeometryPrimitiveType) -> SCNGeometryPrimitiveType {
       switch type {
       case .line:
               return .line
       case .triangle:
               return .triangles
       }
    }
}


struct BoundingBox {
  let min: SCNVector3
  let max: SCNVector3

  init(_ boundTuple: (min: SCNVector3, max: SCNVector3)) {
    min = boundTuple.min
    max = boundTuple.max
  }

  func contains(_ point: SCNVector3) -> Bool {
    let contains =
    min.x <= point.x &&
    min.y <= point.y &&
    min.z <= point.z &&

    max.x > point.x &&
    max.y > point.y &&
    max.z > point.z

    return contains
  }
}
