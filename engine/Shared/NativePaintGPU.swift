import Metal
import SceneKit
import simd

/// UV atlas painting entirely on GPU. One depth pass prevents painting through
/// the model; one UV pass paints every visible island without CPU hit testing.
final class NativePaintGPU {
 struct Vertex {var position:SIMD4<Float>;var uv:SIMD2<Float>;var padding:SIMD2<Float> = .zero}
 struct Uniforms {var world:simd_float4x4;var projection:simd_float4x4;var brush:SIMD4<Float>;var ink:SIMD4<Float>;var viewport:SIMD4<Float>}
 struct Mesh {let node:SCNNode;let vertices:MTLBuffer;let indices:MTLBuffer;let count:Int}
 let device:MTLDevice;let queue:MTLCommandQueue;let depthPipeline:MTLRenderPipelineState;let paintPipeline:MTLRenderPipelineState;let depthState:MTLDepthStencilState
 var front:MTLTexture;var back:MTLTexture;let depth:MTLTexture;var meshes=[Mesh]()
 init()throws {
  guard let d=MTLCreateSystemDefaultDevice(),let q=d.makeCommandQueue() else{throw NativeGLBError.invalid("Metal unavailable")};device=d;queue=q
  let shader="""
  #include <metal_stdlib>
  using namespace metal;
  struct Vertex {float4 position;float2 uv;float2 padding;};
  struct Uniforms {float4x4 world;float4x4 projection;float4 brush;float4 ink;float4 viewport;};
  struct Out {float4 position [[position]];float4 projected;float2 uv;};
  vertex Out depthVertex(uint id [[vertex_id]],const device Vertex* vertices [[buffer(0)]],constant Uniforms& u [[buffer(1)]]) {
   Out o;o.projected=u.projection*u.world*vertices[id].position;o.position=o.projected;o.position.z=(o.position.z+o.position.w)*.5;o.uv=vertices[id].uv;return o;
  }
  vertex Out paintVertex(uint id [[vertex_id]],const device Vertex* vertices [[buffer(0)]],constant Uniforms& u [[buffer(1)]]) {
   Out o;o.uv=vertices[id].uv;o.position=float4(o.uv.x*2.-1.,1.-o.uv.y*2.,0,1);o.projected=u.projection*u.world*vertices[id].position;return o;
  }
  fragment float4 paintFragment(Out in [[stage_in]],constant Uniforms& u [[buffer(1)]],texture2d<float> previous [[texture(0)]],depth2d<float> depths [[texture(1)]]) {
   constexpr sampler nearest(filter::nearest,address::clamp_to_edge);
   float4 old=previous.sample(nearest,in.uv);float3 p=in.projected.xyz/in.projected.w;float2 screen=float2(p.x*.5+.5,.5-p.y*.5);
   float dist=length((screen-u.brush.xy)*u.viewport.xy);float mask=(1.-smoothstep(u.brush.z*.8,u.brush.z,dist))*u.brush.w;
   if(in.projected.w<=0||any(screen<0)||any(screen>1)||p.z*.5+.5>depths.sample(nearest,screen)+.0001)mask=0;
   return float4(mix(old.rgb,u.ink.rgb,mask),1);
  }
  """
  let library=try d.makeLibrary(source:shader,options:nil),dp=MTLRenderPipelineDescriptor();dp.vertexFunction=library.makeFunction(name:"depthVertex");dp.depthAttachmentPixelFormat = .depth32Float;depthPipeline=try d.makeRenderPipelineState(descriptor:dp)
  let pp=MTLRenderPipelineDescriptor();pp.vertexFunction=library.makeFunction(name:"paintVertex");pp.fragmentFunction=library.makeFunction(name:"paintFragment");pp.colorAttachments[0].pixelFormat = .rgba8Unorm;paintPipeline=try d.makeRenderPipelineState(descriptor:pp)
  let ds=MTLDepthStencilDescriptor();ds.depthCompareFunction = .lessEqual;ds.isDepthWriteEnabled=true;depthState=d.makeDepthStencilState(descriptor:ds)!
  func texture(_ format:MTLPixelFormat,_ width:Int,_ height:Int)->MTLTexture {let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:format,width:width,height:height,mipmapped:false);desc.usage=[.renderTarget,.shaderRead];desc.storageMode=format == .depth32Float ? .private : .shared;return d.makeTexture(descriptor:desc)!}
  front=texture(.rgba8Unorm,1024,1024);back=texture(.rgba8Unorm,1024,1024);depth=texture(.depth32Float,1024,1024);clear()
 }
 func attach(_ root:SCNNode)throws {
  meshes=[];var error:Error?
  root.enumerateChildNodes{node,_ in
   guard let geometry=node.geometry,let position=geometry.sources(for:.vertex).first,let uv=geometry.sources(for:.texcoord).first else{return}
   guard position.bytesPerComponent==4,uv.bytesPerComponent==4 else{error=NativeGLBError.invalid("Unsupported GPU vertex format");return}
   func f(_ source:SCNGeometrySource,_ i:Int,_ c:Int)->Float {source.data.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:source.dataOffset+i*source.dataStride+c*4,as:Float.self)}}
   var vertices=(0..<position.vectorCount).map{Vertex(position:SIMD4(f(position,$0,0),f(position,$0,1),f(position,$0,2),1),uv:SIMD2(f(uv,$0,0),f(uv,$0,1)))}
   guard let buffer=vertices.withUnsafeMutableBytes({device.makeBuffer(bytes:$0.baseAddress!,length:$0.count)}) else{return}
   for element in geometry.elements {let size=element.bytesPerIndex,count=element.primitiveCount*3;var indices=element.data.withUnsafeBytes{raw in (0..<count).map{i->UInt32 in let offset=i*size;return size==1 ? UInt32(raw[offset]) : size==2 ? UInt32(raw.loadUnaligned(fromByteOffset:offset,as:UInt16.self)) : raw.loadUnaligned(fromByteOffset:offset,as:UInt32.self)}}
    if let indexBuffer=indices.withUnsafeMutableBytes({device.makeBuffer(bytes:$0.baseAddress!,length:$0.count)}){meshes.append(Mesh(node:node,vertices:buffer,indices:indexBuffer,count:count))}
   }
  };if let error=error{throw error};bind()
 }
 func bind(){for mesh in meshes{mesh.node.geometry?.materials.forEach{material in material.diffuse.contents=front;material.diffuse.contentsTransform=SCNMatrix4Identity}}}
 func clear(){let command=queue.makeCommandBuffer()!;for texture in [front,back]{let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=texture;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store;pass.colorAttachments[0].clearColor=MTLClearColorMake(1,1,1,1);command.makeRenderCommandEncoder(descriptor:pass)?.endEncoding()};command.commit();command.waitUntilCompleted()}
 func snapshot()->Data{let fence=queue.makeCommandBuffer()!;fence.commit();fence.waitUntilCompleted();var bytes=Data(count:1024*4096);bytes.withUnsafeMutableBytes{front.getBytes($0.baseAddress!,bytesPerRow:4096,from:MTLRegionMake2D(0,0,1024,1024),mipmapLevel:0)};return bytes}
 func restore(_ bytes:Data){guard bytes.count==1024*4096 else{return};let fence=queue.makeCommandBuffer()!;fence.commit();fence.waitUntilCompleted();bytes.withUnsafeBytes{front.replace(region:MTLRegionMake2D(0,0,1024,1024),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:4096)};bind()}
 func stamp(_ point:CGPoint,size:CGSize,camera:SCNNode,radius:CGFloat,opacity:CGFloat,color:UIColor){
  guard !meshes.isEmpty,size.width>0,size.height>0,let command=queue.makeCommandBuffer() else{return}
  let aspect=Float(size.width/size.height),f:Float=1/tan(35*Float.pi/360),near:Float=0.01,far:Float=50
  let projection=simd_float4x4(SIMD4(f/aspect,0,0,0),SIMD4(0,f,0,0),SIMD4(0,0,(far+near)/(near-far),-1),SIMD4(0,0,2*far*near/(near-far),0))*simd_inverse(camera.simdWorldTransform)
  let converted=color.cgColor.converted(to:CGColorSpace(name:CGColorSpace.linearSRGB)!,intent:.defaultIntent,options:nil)!,components=converted.components ?? [0,0,1,1]
  var uniforms=Uniforms(world:matrix_identity_float4x4,projection:projection,brush:SIMD4(Float(point.x/size.width),Float(point.y/size.height),Float(radius),Float(opacity)),ink:SIMD4(Float(components[0]),Float(components[1]),Float(components[2]),1),viewport:SIMD4(Float(size.width),Float(size.height),0,0))
  let depthPass=MTLRenderPassDescriptor();depthPass.depthAttachment.texture=depth;depthPass.depthAttachment.loadAction = .clear;depthPass.depthAttachment.storeAction = .store;depthPass.depthAttachment.clearDepth=1
  if let encoder=command.makeRenderCommandEncoder(descriptor:depthPass){encoder.setRenderPipelineState(depthPipeline);encoder.setDepthStencilState(depthState);encoder.setCullMode(.none);for mesh in meshes{uniforms.world=mesh.node.simdWorldTransform;encoder.setVertexBuffer(mesh.vertices,offset:0,index:0);encoder.setVertexBytes(&uniforms,length:MemoryLayout<Uniforms>.stride,index:1);encoder.drawIndexedPrimitives(type:.triangle,indexCount:mesh.count,indexType:.uint32,indexBuffer:mesh.indices,indexBufferOffset:0)};encoder.endEncoding()}
  let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=back;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store;pass.colorAttachments[0].clearColor=MTLClearColorMake(1,1,1,1)
  if let encoder=command.makeRenderCommandEncoder(descriptor:pass){encoder.setRenderPipelineState(paintPipeline);encoder.setCullMode(.none);encoder.setFragmentTexture(front,index:0);encoder.setFragmentTexture(depth,index:1);for mesh in meshes{uniforms.world=mesh.node.simdWorldTransform;encoder.setVertexBuffer(mesh.vertices,offset:0,index:0);encoder.setVertexBytes(&uniforms,length:MemoryLayout<Uniforms>.stride,index:1);encoder.setFragmentBytes(&uniforms,length:MemoryLayout<Uniforms>.stride,index:1);encoder.drawIndexedPrimitives(type:.triangle,indexCount:mesh.count,indexType:.uint32,indexBuffer:mesh.indices,indexBufferOffset:0)};encoder.endEncoding()}
  command.commit();command.waitUntilCompleted();swap(&front,&back);bind()
 }
}
