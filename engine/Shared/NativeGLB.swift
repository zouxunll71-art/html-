import SceneKit

/// Deliberately bounded glTF 2 reader: embedded, static, indexed triangle meshes.
/// Unsupported compression/animation is an error, never a poster fallback.
enum NativeGLBError: Error, LocalizedError {
 case invalid(String)
 var errorDescription:String? { if case .invalid(let message)=self{return message};return nil }
}
struct NativeGLB {
 let json:[String:Any];let bytes:Data
 init(_ data:Data)throws {
  func word(_ offset:Int)throws->UInt32 {guard offset>=0,offset+4<=data.count else{throw NativeGLBError.invalid("Truncated GLB")};return data.subdata(in:offset..<offset+4).withUnsafeBytes{$0.loadUnaligned(as:UInt32.self).littleEndian}}
  guard try word(0)==0x46546c67,try word(4)==2,Int(try word(8))==data.count else{throw NativeGLBError.invalid("Invalid GLB 2 header")}
  var offset=12,document:[String:Any]?,binary:Data?
  while offset+8<=data.count {let length=Int(try word(offset)),type=try word(offset+4);offset+=8;guard length<=data.count-offset else{throw NativeGLBError.invalid("Invalid GLB chunk")};let chunk=data.subdata(in:offset..<offset+length);if type==0x4e4f534a{document=try JSONSerialization.jsonObject(with:chunk) as? [String:Any]};if type==0x004e4942{binary=chunk};offset+=length}
  guard let doc=document,let bin=binary else{throw NativeGLBError.invalid("Missing GLB data")}
  guard (doc["extensionsRequired"] as? [String] ?? []).isEmpty,(doc["animations"] as? [Any] ?? []).isEmpty,(doc["skins"] as? [Any] ?? []).isEmpty else{throw NativeGLBError.invalid("Animated, skinned or compressed GLB is not supported")}
  json=doc;bytes=bin
 }
 func accessor(_ index:Int,types:Set<Int>,components:Int)throws->(Data,Int,Int){
  let accessors=json["accessors"] as? [[String:Any]] ?? [],views=json["bufferViews"] as? [[String:Any]] ?? []
  guard accessors.indices.contains(index) else{throw NativeGLBError.invalid("Invalid accessor")};let a=accessors[index]
  guard let vi=a["bufferView"] as? Int,views.indices.contains(vi),let type=a["componentType"] as? Int,types.contains(type),let count=a["count"] as? Int,count>0,count<=3_000_000,a["sparse"]==nil,a["normalized"] as? Bool != true, a["type"] as? String == [1:"SCALAR",2:"VEC2",3:"VEC3"][components] else{throw NativeGLBError.invalid("Unsupported accessor format")}
  let v=views[vi],size=type==5121 ? 1 : type==5123 ? 2 : 4,stride=v["byteStride"] as? Int ?? components*size,start=(v["byteOffset"] as? Int ?? 0)+(a["byteOffset"] as? Int ?? 0),length=v["byteLength"] as? Int ?? 0
  guard v["buffer"] as? Int ?? 0 == 0,stride>=components*size,start>=0,length>=0,start+(count-1)*stride+components*size<=bytes.count,(a["byteOffset"] as? Int ?? 0)+(count-1)*stride+components*size<=length else{throw NativeGLBError.invalid("Accessor exceeds buffer")}
  var packed=Data();packed.reserveCapacity(count*components*size)
  for i in 0..<count{packed.append(bytes.subdata(in:start+i*stride..<start+i*stride+components*size))}
  if type==5126 {let finite=packed.withUnsafeBytes{raw in (0..<count*components).allSatisfy{Float(bitPattern:raw.loadUnaligned(fromByteOffset:$0*4,as:UInt32.self).littleEndian).isFinite}};guard finite else{throw NativeGLBError.invalid("Non-finite model coordinates")}}
  return(packed,count,size)
 }
 func scene()throws->SCNNode {
  let meshes=json["meshes"] as? [[String:Any]] ?? [],nodes=json["nodes"] as? [[String:Any]] ?? [],scenes=json["scenes"] as? [[String:Any]] ?? []
  let sceneIndex=json["scene"] as? Int ?? 0
  guard scenes.indices.contains(sceneIndex) else{throw NativeGLBError.invalid("Missing model scene")}
  var active=Set<Int>(),used=Set<Int>()
  func node(_ index:Int,depth:Int)throws->SCNNode {
   guard nodes.indices.contains(index),depth<128,!active.contains(index),!used.contains(index) else{throw NativeGLBError.invalid("Invalid model hierarchy")};active.insert(index);used.insert(index);defer{active.remove(index)}
   let data=nodes[index],result=SCNNode()
   if let matrix=data["matrix"] as? [Float],matrix.count==16 {result.simdTransform=simd_float4x4(SIMD4(matrix[0],matrix[1],matrix[2],matrix[3]),SIMD4(matrix[4],matrix[5],matrix[6],matrix[7]),SIMD4(matrix[8],matrix[9],matrix[10],matrix[11]),SIMD4(matrix[12],matrix[13],matrix[14],matrix[15]))}
   else {if let p=data["translation"] as? [Float],p.count==3{result.position=SCNVector3(p[0],p[1],p[2])};if let p=data["scale"] as? [Float],p.count==3{result.scale=SCNVector3(p[0],p[1],p[2])};if let q=data["rotation"] as? [Float],q.count==4{result.orientation=SCNQuaternion(q[0],q[1],q[2],q[3])}}
   if let mi=data["mesh"] as? Int {
    guard meshes.indices.contains(mi),let primitives=meshes[mi]["primitives"] as? [[String:Any]],!primitives.isEmpty else{throw NativeGLBError.invalid("Invalid mesh")}
    for primitive in primitives {
     guard primitive["mode"] as? Int ?? 4 == 4,primitive["targets"]==nil,primitive["extensions"]==nil,let attrs=primitive["attributes"] as? [String:Int],let pos=attrs["POSITION"],let uv=attrs["TEXCOORD_0"] else{throw NativeGLBError.invalid("Painting needs static triangles with UV0")}
     let (vertices,count,_)=try accessor(pos,types:[5126],components:3), (coords,uvCount,_)=try accessor(uv,types:[5126],components:2)
     guard count==uvCount else{throw NativeGLBError.invalid("UV count differs from vertices")}
     var sources=[SCNGeometrySource(data:vertices,semantic:.vertex,vectorCount:count,usesFloatComponents:true,componentsPerVector:3,bytesPerComponent:4,dataOffset:0,dataStride:12),SCNGeometrySource(data:coords,semantic:.texcoord,vectorCount:count,usesFloatComponents:true,componentsPerVector:2,bytesPerComponent:4,dataOffset:0,dataStride:8)]
     if let normal=attrs["NORMAL"]{let(n,nc,_)=try accessor(normal,types:[5126],components:3);guard nc==count else{throw NativeGLBError.invalid("Normal count mismatch")};sources.append(SCNGeometrySource(data:n,semantic:.normal,vectorCount:count,usesFloatComponents:true,componentsPerVector:3,bytesPerComponent:4,dataOffset:0,dataStride:12))}
     let indices:Data,indexCount:Int,indexSize:Int
     if let ii=primitive["indices"] as? Int {(indices,indexCount,indexSize)=try accessor(ii,types:[5121,5123,5125],components:1)}else{var values=(0..<count).map{UInt32($0).littleEndian};indices=values.withUnsafeMutableBytes{Data($0)};indexCount=count;indexSize=4}
     guard indexCount%3==0 else{throw NativeGLBError.invalid("Incomplete triangles")}
     let valid=indices.withUnsafeBytes{raw in (0..<indexCount).allSatisfy{i in let offset=i*indexSize;let value=indexSize==1 ? UInt32(raw[offset]) : indexSize==2 ? UInt32(raw.loadUnaligned(fromByteOffset:offset,as:UInt16.self).littleEndian) : raw.loadUnaligned(fromByteOffset:offset,as:UInt32.self).littleEndian;return value<UInt32(count)}}
     guard valid else{throw NativeGLBError.invalid("Index exceeds vertices")}
     let geometry=SCNGeometry(sources:sources,elements:[SCNGeometryElement(data:indices,primitiveType:.triangles,primitiveCount:indexCount/3,bytesPerIndex:indexSize)])
     let material=SCNMaterial();material.lightingModel = .physicallyBased;material.diffuse.contents=UIColor.white;material.roughness.contents=0.65;material.metalness.contents=0;material.isDoubleSided=true;material.diffuse.wrapS = .clamp;material.diffuse.wrapT = .clamp;geometry.materials=[material];result.addChildNode(SCNNode(geometry:geometry))
    }
   }
   for child in data["children"] as? [Int] ?? []{result.addChildNode(try node(child,depth:depth+1))};return result
  }
  let root=SCNNode();for index in scenes[sceneIndex]["nodes"] as? [Int] ?? []{root.addChildNode(try node(index,depth:0))}
  let(minimum,maximum)=root.boundingBox;let span=max(maximum.x-minimum.x,max(maximum.y-minimum.y,maximum.z-minimum.z))
  guard span.isFinite,span>0 else{throw NativeGLBError.invalid("Empty model")}
  root.position=SCNVector3(-(minimum.x+maximum.x)/2,-(minimum.y+maximum.y)/2,-(minimum.z+maximum.z)/2)
  let normalized=SCNNode();normalized.addChildNode(root);let scale=1.8/span;normalized.scale=SCNVector3(scale,scale,scale);return normalized
 }
}
