//
//  ScanViewController.swift
//  scanUrBuddy
//
//  Created by Quentin Reiser on 2/23/22.
//  Copyright © 2022 Metal by Example. All rights reserved.
//

import Foundation
import UIKit
import ARKit
import MetalKit
import SceneKit.ModelIO
import VideoToolbox


enum ScanState: Int, CaseIterable {
    case idle
    case scanning
    case viewing
}


class ScanViewController: UIViewController, MTKViewDelegate, ARSessionDelegate, ARSCNViewDelegate, RendererDelegate {
    
    var session: ARSession!
    var wConfig: ARWorldTrackingConfiguration!
    var sConfig: ARWorldTrackingConfiguration!
    var renderer: Renderer!
    var mtkView: MTKView!
    
    var state: ScanState = .idle
    
    var arView: ARSCNView!
    var arBounds: CGRect!
    
    var scanButton: UIButton!
    var tLabel: UILabel!
    
    var scanNode: SCNNode!
    var scanTexture: UIImage!
    var textureImgs: [Int: UIImage] = [:]
    
    var allVerts: [[SCNVector3]] = []
    var allNorms: [[SCNVector3]] = []
    var allTCrds: [[vector_float2]] = []
    
    var cVerts: [SCNVector3] = []
    var cNorms: [SCNVector3] = []
    var cTCrds: [vector_float2] = []
    var nFaces: [[UInt32]] = []
    
    var defaults: UserDefaults!
    var hapty: UIImpactFeedbackGenerator!
    
    
    override func viewDidLoad() {
        
        super.viewDidLoad()

        session = ARSession()
        session.delegate = self
        
        wConfig = ARWorldTrackingConfiguration()
        wConfig.sceneReconstruction = .mesh
        wConfig.frameSemantics = [.sceneDepth]
        
        mtkView = MTKView(frame: view.frame)
        view.addSubview(mtkView)

        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.backgroundColor = .black
        mtkView.delegate = self

        renderer = Renderer(session: session, view: mtkView)
        renderer.delegate = self
        
        setupControls()
        
        defaults = UserDefaults.standard
    }
    
        
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        session.run(wConfig)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        session.pause()
    }
    
    func reset() {
        textureImgs = [:]
        
        allVerts = []
        allNorms = []
        allTCrds = []
        
        cVerts = []
        cNorms = []
        cTCrds = []
        nFaces = []
        
        renderer.worldMeshes = []
        renderer.textureCloud = []
        
        arView.removeFromSuperview()
        session.run(wConfig)
    }
    
    
    @objc func scanTapped() {
        
        state = state.next()
        
        switch state {
        case .idle:
            reset()
            scanButton.setTitle("scan", for: .normal)
            tLabel.text = "ready to scan"
        case .scanning:
            // place box in front of you and start scanning
            let lPos = SCNVector3Make(0, 0, -0.5)
            let cTrans = session.currentFrame!.camera.transform
            let cMatrix4 = SCNMatrix4(cTrans)
            
            let pMatrix4 = SCNMatrix4MakeTranslation(lPos.x, lPos.y, lPos.z)
            let wTrans = SCNMatrix4Mult(pMatrix4, cMatrix4)
            let wPos = SCNVector3(wTrans.m41, wTrans.m42, wTrans.m43)
            
            renderer.placeBox(pos: wPos)
            scanButton.setTitle("done", for: .normal)
            tLabel.text = "scanning"
        case .viewing:
            session.pause()
            scanButton.setTitle("restart", for: .normal)
            tLabel.text = "viewing scan"
            setupScanView()
        }
        
        renderer.state = state
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        
        // save a texture frame by tapping
        // ideally this would be done with a timer, or by moving a certain distance
        if state == .scanning {
            renderer.saveTextureFrame()
        }
    }
    
    
    // displays a sphere in the location where each texture was saved
    func visualizeTextureCloud() {
        
        var textureCloud = renderer.textureCloud
        textureCloud.sort { $0.dist < $1.dist }
        
        for frame in textureCloud {
            
            print(frame.dist)
            
            let sphere = SCNSphere(radius: 0.03)
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor.blue
            sphere.materials = [mat]
            let frameNode = SCNNode(geometry: sphere)
            frameNode.position = frame.pos
            arView.scene.rootNode.addChildNode(frameNode)
        }
    }
    
    func didSaveFrame(renderer: Renderer) {
        hapty.impactOccurred()
    }
    
    
    
    func makeTexturedMesh() {
        
        let worldMeshes = renderer.worldMeshes
        let textureCloud = renderer.textureCloud
        
        print("texture images: \(textureImgs.count)")
        
        // each 'mesh' is a chunk of the whole scan
        for mesh in worldMeshes {
            
            let aTrans = SCNMatrix4(mesh.transform)
            
            let vertices: ARGeometrySource = mesh.vertices
            let normals: ARGeometrySource = mesh.normals
            let faces: ARGeometryElement = mesh.submesh
            
            var texture: UIImage!
            
            // a face is just a list of three indices, each representing a vertex
            for f in 0..<faces.count {
                
                // check to see if each vertex of the face is inside of our box
                var c = 0
                let face = face(at: f, faces: faces)
                for fv in face {
                    // this is set by the renderer
                    if mesh.inBox[fv] == 1 {
                        c += 1
                    }
                }
                
                guard c == 3 else {continue}
                
                // all verts of the face are in the box, so the triangle is visible
                var fVerts: [SCNVector3] = []
                var fNorms: [SCNVector3] = []
                var tCoords: [vector_float2] = []
                
                // convert each vertex and normal to world coordinates
                // get the texture coordinates
                for fv in face {
                    
                    let vert = vertex(at: UInt32(fv), vertices: vertices)
                    let vTrans = SCNMatrix4MakeTranslation(vert[0], vert[1], vert[2])
                    let wTrans = SCNMatrix4Mult(vTrans, aTrans)
                    let wPos = SCNVector3(wTrans.m41, wTrans.m42, wTrans.m43)
                    fVerts.append(wPos)
                    
                    let norm = normal(at: UInt32(fv), normals: normals)
                    let nTrans = SCNMatrix4MakeTranslation(norm[0], norm[1], norm[2])
                    let wNTrans = SCNMatrix4Mult(nTrans, aTrans)
                    let wNPos = SCNVector3(wNTrans.m41, wTrans.m42, wNTrans.m43)
                    fNorms.append(wNPos)
                    
                    
                    // here's where you would find the frame that best fits
                    // for simplicity, just use the last frame here
                    let tFrame = textureCloud.last!.frame
                    let tCoord = getTextureCoord(frame: tFrame, vert: vert, aTrans: mesh.transform)
                    tCoords.append(tCoord)
                    texture = textureImgs[textureCloud.count - 1]
                    
                    // visualize the normals if you want
                    if mesh.inBox[fv] == 1 {
                        //let normVis = lineBetweenNodes(positionA: wPos, positionB: wNPos, inScene: arView.scene)
                        //arView.scene.rootNode.addChildNode(normVis)
                    }
                }
                allVerts.append(fVerts)
                allNorms.append(fNorms)
                allTCrds.append(tCoords)
                
                // make a single triangle mesh out each face
                let vertsSource = SCNGeometrySource(vertices: fVerts)
                let normsSource = SCNGeometrySource(normals: fNorms)
                let facesSource = SCNGeometryElement(indices: [UInt32(0), UInt32(1), UInt32(2)], primitiveType: .triangles)
                let textrSource = SCNGeometrySource(textureCoordinates: tCoords)
                let geom = SCNGeometry(sources: [vertsSource, normsSource, textrSource], elements: [facesSource])
                
                // texture it with a saved camera frame
                let mat = SCNMaterial()
                mat.diffuse.contents = texture
                mat.isDoubleSided = false
                geom.materials = [mat]
                let meshNode = SCNNode(geometry: geom)
                
                DispatchQueue.main.async {
                    self.scanNode.addChildNode(meshNode)
                }
            }
        }
    }
    
    
    // takes all the mesh node geometries and recombines into one geometry
    func recombineGeoms() -> SCNNode {
        
        for f in 0..<allVerts.count {
            for v in 0..<allVerts[f].count {
                let vert = allVerts[f][v]
                let norm = allNorms[f][v]
                let tCrd = allTCrds[f][v]
                if cVerts.firstIndex(where: { $0.x == vert.x && $0.y == vert.y && $0.z == vert.z}) == nil {
                    cVerts.append(vert)
                    cNorms.append(norm)
                    cTCrds.append(tCrd)
                }
            }
        }
        
        for f in 0..<allVerts.count {
            var fIndices: [UInt32] = []
            for v in 0..<allVerts[f].count {
                let vert = allVerts[f][v]
                if let i = cVerts.firstIndex(where: { $0.x == vert.x && $0.y == vert.y && $0.z == vert.z}) {
                    fIndices.append(UInt32(i))
                }
            }
            nFaces.append(fIndices)
        }
        
        let vertsSource = SCNGeometrySource(vertices: cVerts)
        let normsSource = SCNGeometrySource(normals: cNorms)
        let facesSource = SCNGeometryElement(indices: nFaces.flatMap{$0}, primitiveType: .triangles)
        let textrSource = SCNGeometrySource(textureCoordinates: cTCrds)
        
        let frame = renderer.textureCloud[0].frame
        let texture = getTextureImage(frame: frame)
        
        let geom = SCNGeometry(sources: [vertsSource, normsSource, textrSource], elements: [facesSource])
        let mat = SCNMaterial()
        mat.diffuse.contents = texture
        mat.isDoubleSided = false
        geom.materials = [mat]
        let meshNode = SCNNode(geometry: geom)
        return meshNode
    }
    
    
    func getTextureCoord(frame: ARFrame, vert: SIMD3<Float>, aTrans: simd_float4x4) -> vector_float2 {
        
        // convert vertex to world coordinates
        let cam = frame.camera
        let size = cam.imageResolution
        let vertex4 = vector_float4(vert.x, vert.y, vert.z, 1)
        let world_vertex4 = simd_mul(aTrans, vertex4)
        let world_vector3 = simd_float3(x: world_vertex4.x, y: world_vertex4.y, z: world_vertex4.z)
        
        // project the point into the camera image to get u,v
        let pt = cam.projectPoint(world_vector3,
            orientation: .portrait,
            viewportSize: CGSize(
                width: CGFloat(size.height),
                height: CGFloat(size.width)))
        let v = 1.0 - Float(pt.x) / Float(size.height)
        let u = Float(pt.y) / Float(size.width)
        
        let tCoord = vector_float2(u, v)
        
        return tCoord
    }
    
    
    func getTextureCoords(frame: ARFrame, vertices: ARGeometrySource, aTrans: simd_float4x4) -> [vector_float2] {
        
        var tCoords: [vector_float2] = []
        
        for v in 0..<vertices.count {
            let vert = vertex(at: UInt32(v), vertices: vertices)
            let tCoord = getTextureCoord(frame: frame, vert: vert, aTrans: aTrans)
            
            tCoords.append(tCoord)
        }
        
        return tCoords
    }
    
    
    // save mesh and texture
    func exportMesh(geom: SCNGeometry, name: String) {
        
        let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let asset = MDLAsset()
        let mesh = MDLMesh(scnGeometry: geom)
        asset.add(mesh)
        
        do {
            // try to save the .obj file
            try asset.export(to: URL(fileURLWithPath: path + "/\(name)" + ".obj"))
            print("Mesh with name '\(name)' exported")
            
            // save the texture
            let data = scanTexture.pngData()
            defaults.set(data, forKey: "scan_texture_\(name)")
        } catch {
            print("Can't write mesh to url")
        }
    }
    
    
    // load mesh and texture
    func loadMesh(name: String) -> SCNGeometry? {
        
        let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let url = URL(fileURLWithPath: path + "/\(name)" + ".obj")
        let asset = MDLAsset(url: url)
        if let mesh = asset.object(at: 0) as? MDLMesh {
            let geom = SCNGeometry(mdlMesh: mesh)
            
            // you'll need this too if you want to texture it
            let texture = defaults.value(forKey: "scan_texture_\(name)")
            return geom
        } else {
            return nil
        }
    }
    
    
    
    func setupScanView() {
        
        arView = ARSCNView(frame: view.frame)
        arView.delegate = self
        arView.autoenablesDefaultLighting = false
        arBounds = arView.bounds
        
        sConfig = ARWorldTrackingConfiguration()
        sConfig.sceneReconstruction = .mesh
        sConfig.planeDetection = [.horizontal, .vertical]
        arView.session.run(sConfig, options: [])
        view.addSubview(arView)
        
        view.bringSubviewToFront(scanButton)
        
        scanNode = SCNNode()
        scanNode.position = SCNVector3(0,0,0)
        arView.scene.rootNode.addChildNode(scanNode)
        
        for i in 0..<renderer.textureCloud.count {
            let tFrame = renderer.textureCloud[i]
            let img = getTextureImage(frame: tFrame.frame)
            textureImgs[i] = img
        }
        
        //visualizeTextureCloud()
        makeTexturedMesh()
    }
    
    
    
    func setupControls() {
        
        let tlWidth = view.frame.width * 0.88
        let tlHeight = tlWidth * 0.18
        let tlX = view.frame.width * 0.5 - (tlWidth / 2)
        let tlY = view.frame.height * 0.14
        let tlRect = CGRect(x: tlX, y: tlY, width: tlWidth, height: tlHeight)
        tLabel = UILabel(frame: tlRect)
        tLabel.font = UIFont(name: "Avenir", size: 18)
        tLabel.textAlignment = .center
        tLabel.adjustsFontSizeToFitWidth = true
        tLabel.textColor = UIColor.lightGray
        tLabel.text = "ready to scan"
        view.addSubview(tLabel)
        
        
        let bWidth = view.frame.width * 0.32
        let bHeight = bWidth * 0.44
        let bX = view.frame.width * 0.5 - (bWidth / 2)
        let bY = view.frame.height * 0.9
        let bRect = CGRect(x: bX, y: bY, width: bWidth, height: bHeight)
        scanButton = UIButton(frame: bRect)
        scanButton.alpha = 1.0
        scanButton.isEnabled = true
        scanButton.layer.cornerRadius = bHeight / 2
        scanButton.backgroundColor = UIColor.darkGray
        scanButton.titleLabel?.font = UIFont(name: "Avenir", size: 20)
        scanButton.setTitleColor(UIColor.white, for: .normal)
        scanButton.setTitle("scan", for: .normal)
        let tap = UITapGestureRecognizer(target: self, action: #selector(scanTapped))
        scanButton.addGestureRecognizer(tap)
        view.addSubview(scanButton)
        
        hapty = UIImpactFeedbackGenerator(style: .medium)
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        print("drawable size: \(size)")
    }

    func draw(in view: MTKView) {
        renderer.update()
    }
    
    override var prefersHomeIndicatorAutoHidden: Bool {return true}
    override var prefersStatusBarHidden: Bool {return true}
}


extension CGImage {
    
  public static func create(pixelBuffer: CVPixelBuffer) -> CGImage? {
    var cgImage: CGImage?
    VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
    return cgImage
  }
}

extension Dictionary where Value: Comparable {
    var sortedByValue: [(Key, Value)] { return Array(self).sorted { $0.1 < $1.1} }
}
extension Dictionary where Key: Comparable {
    var sortedByKey: [(Key, Value)] { return Array(self).sorted { $0.0 < $1.0 } }
}

extension CaseIterable where Self: Equatable {
    func next() -> Self {
        let all = Self.allCases
        let idx = all.firstIndex(of: self)!
        let next = all.index(after: idx)
        return all[next == all.endIndex ? all.startIndex : next]
    }
}
