# Oblique cross-section (MPR) rendering of a voxel volume, and drawing the cut plane on an overview

## Summary
Every mature viewer parameterizes an oblique slice the same way: a 4x4 "slice-to-world" matrix whose first three columns are the in-plane x unit vector, in-plane y unit vector and plane normal, and whose fourth column is the plane origin (VTK vtkImageReslice ResliceAxes; 3D Slicer vtkMRMLSliceNode::SliceToRAS; Cornerstone3D's camera {viewPlaneNormal, viewUp, viewRight}). The in-plane vectors are derived from a normal plus an "up"/"transverse" hint by Gram-Schmidt cross products (Slicer SetSliceToRASByNTP: c = n x t, t = c x n; Cornerstone: viewRight = viewUp x viewPlaneNormal). Rotation about a fixed anchor is expressed as T(anchor) * R(axis, angle) * T(-anchor) pre-multiplied onto the slice matrix (Slicer vtkMRMLSliceIntersectionWidget::Rotate; Cornerstone CrosshairsTool uses the identical translate/rotate/translate matrix builder), and translation is "move the origin along the normal" (Slicer SetSliceOffset / JumpSliceByOffsetting). Sampling is done by converting the output pixel grid once into continuous voxel-index space and then stepping per pixel and per row with constant index deltas (VTK vtkImageResliceExecute xAxis/yAxis/zAxis increments; Cornerstone PlanarCPUVolumeSampler xStepIndexDelta/yStepIndexDelta), with trilinear interpolation for intensity (VTK vtkImageNLCInterpolate::Trilinear: floor, fractional weights, clamp, 8 taps) and nearest-neighbour for label maps (Slicer vtkMRMLSliceLayerLogic forces NearestNeighbor for labelmap volumes). Slicer's 2D slice views and open-dicom-viewer's MPR are CPU resamplers; Cornerstone ships both a CPU sampler and a GPU path; thalesmms/mtk does MPR as a Metal compute kernel whose uniforms are exactly planeOrigin/planeX/planeY/planeNormal. For our 256x256 output the CPU path is comfortably under 2 ms with DispatchQueue.concurrentPerform and avoids Metal toolchain risk today, so we should ship CPU-into-CGImage first while keeping the plane struct shaped like mtk's MPRSlabUniforms so the kernel can be dropped in later. The reference cut line on an overview is computed by intersecting the four edges of the cut rectangle with the overview plane (Slicer IntersectWithFinitePlane; Cornerstone ReferenceLinesTool linePlaneIntersection on the image corners), skipping when the planes are parallel, and drawing the resulting segment in the overview's 2D pixel space; because our tilt axis is patient left-right, the line only visibly rotates on a side (sagittal) overview, not on a front view.

## Precedents
- Kitware/VTK — https://github.com/Kitware/VTK/blob/0b16bd70aff267a2bd1cd2d136d5fb04f977a3ed/Imaging/Core/vtkImageReslice.h#L75-L99 — ResliceAxes doc: 'The first column of the matrix specifies the x-axis vector (the fourth element must be set to zero), the second column specifies the y-axis, and the third column the z-axis. The fourth column is the origin of the axes'; SetResliceAxesDirectionCosines(x,y,z) and SetResliceAxesOrigin; interpolation modes Nearest/Linear/Cubic.
- Kitware/VTK — https://github.com/Kitware/VTK/blob/0b16bd70aff267a2bd1cd2d136d5fb04f977a3ed/Imaging/Core/vtkImageReslice.cxx#L3087-L3225 — GetIndexMatrix: inMatrix[i][j] = inInvDirection[3i+j]/inSpacing[i], inMatrix[i][3] -= inInvDirection*inOrigin/inSpacing; outMatrix[i][j] = outDirection*outSpacing[j], outMatrix[i][3]=outOrigin; IndexMatrix = inMatrix * ResliceAxes * outMatrix so output pixel indices map straight to input continuous voxel indices.
- Kitware/VTK — https://github.com/Kitware/VTK/blob/0b16bd70aff267a2bd1cd2d136d5fb04f977a3ed/Imaging/Core/vtkImageReslice.cxx#L636-L694 — Per-pixel incremental transform: xAxis/yAxis/zAxis/origin are the IndexMatrix columns; inPoint0 = origin + idZ*zAxis; inPoint1 = inPoint0 + idY*yAxis; point = inPoint1 + idX*xAxis (same pattern at L2123-L2159 in vtkImageResliceExecute).
- Kitware/VTK — https://github.com/Kitware/VTK/blob/0b16bd70aff267a2bd1cd2d136d5fb04f977a3ed/Imaging/Core/vtkImageInterpolator.cxx#L158-L260 — vtkImageNLCInterpolate::Nearest (Round then Clamp/Wrap/Mirror, single fetch) and ::Trilinear (Floor with fraction fx,fy,fz; inIdX1 = inIdX0 + (fx != 0); clamp both indices to extent; factX/Y/Z = idx*inInc; rx=1-fx etc; ryrz,fyrz,ryfz,fyfz products; 8-tap weighted sum).
- Slicer/Slicer — https://github.com/Slicer/Slicer/blob/136ce06633702ef02eaf6ba13dbd2ef63131bbcc/Libs/MRML/Core/vtkMRMLSliceNode.cxx#L655-L750 — SetSliceToRASByNTP: c = cross(n,t); t = cross(c,n); normalize n,t,c; SliceToRAS columns = [t, c, n], translation = P; para-Axial/Sagittal/Coronal variants permute which of n/c/t become x/y/z columns.
- Slicer/Slicer — https://github.com/Slicer/Slicer/blob/136ce06633702ef02eaf6ba13dbd2ef63131bbcc/Libs/MRML/Core/vtkMRMLSliceNode.cxx#L523-L640 — GetAxialSliceToRASMatrix: cols x=(-1,0,0) [L], y=(0,1,0) [A], z=(0,0,1) [S]; Sagittal: x=(0,-1,0) [P], y=(0,0,1) [S], z=(-1,0,0) [L]; Coronal: x=(-1,0,0), y=(0,0,1), z=(0,1,0) [A]. Preset orientation matrices as explicit column vectors.
- Slicer/Slicer — https://github.com/Slicer/Slicer/blob/136ce06633702ef02eaf6ba13dbd2ef63131bbcc/Libs/MRML/Core/vtkMRMLSliceNode.cxx#L752 — UpdateMatrices: xyToSlice diagonal = FieldOfView[i]/Dimensions[i], translation = -FieldOfView[i]/2 + XYZOrigin[i]; XYToRAS = SliceToRAS * xyToSlice. I.e. pixel (0,0) is the corner and the slice origin is the centre of the field of view.
- Slicer/Slicer — https://github.com/Slicer/Slicer/blob/136ce06633702ef02eaf6ba13dbd2ef63131bbcc/Libs/MRML/Core/vtkMRMLSliceNode.cxx#L1298-L1330 — JumpSliceByOffsetting: d = (p - origin) . normal (normal = column 2 of SliceToRAS); origin += d * normal. Translating the cut to a point without changing orientation.
- Slicer/Slicer — https://github.com/Slicer/Slicer/blob/136ce06633702ef02eaf6ba13dbd2ef63131bbcc/Libs/MRML/Core/vtkMRMLSliceNode.cxx#L1733-L1800 — GetSliceOffset / SetSliceOffset: express the translation in slice coordinates (invert rotation part, take z), set z = offset, transform back; only the origin column changes.
- Slicer/Slicer — https://github.com/Slicer/Slicer/blob/136ce06633702ef02eaf6ba13dbd2ef63131bbcc/Libs/MRML/DisplayableManager/vtkMRMLSliceIntersectionWidget.cxx#L1154-L1180 — Rotate(angleRad): center = XYToRAS * intersection point; transform = Translate(center) . RotateWXYZ(sign*deg, sliceNormal) . Translate(-center), sign = determinant of SliceToRAS rotation; then TransformIntersectingSlices(matrix) which does rotatedSliceToRAS = matrix * SliceToRAS for each other slice (rep L781).
- Slicer/Slicer — https://github.com/Slicer/Slicer/blob/136ce06633702ef02eaf6ba13dbd2ef63131bbcc/Libs/MRML/DisplayableManager/vtkMRMLSliceIntersectionRepresentation2D.cxx#L231-L290 — IntersectWithFinitePlane(n, o, pOrigin, px, py, x0, x1): intersects plane (n,o) with the four edges pOrigin->px, pOrigin->py, (px+py-pOrigin)->py, (px+py-pOrigin)->px via vtkPlane::IntersectWithLine and returns 1 when exactly two hits are found.
- Slicer/Slicer — https://github.com/Slicer/Slicer/blob/136ce06633702ef02eaf6ba13dbd2ef63131bbcc/Libs/MRML/DisplayableManager/vtkMRMLSliceIntersectionRepresentation2D.cxx#L433-L520 — UpdateSliceIntersectionDisplay: rasToXY = inverse(this XYToRAS); intersectingXYToXY = rasToXY * otherXYToRAS; this plane is n=(0,0,1), o=(0,0,0) in its own XY space; the other slice's rectangle corners (0,0), (dimX,0), (0,dimY) are pushed through intersectingXYToXY; IntersectWithFinitePlane gives two endpoints; LineSource->SetPoint1/2; Property->SetColor(intersectingSliceNode->GetLayoutColor()).
- Slicer/Slicer — https://github.com/Slicer/Slicer/blob/136ce06633702ef02eaf6ba13dbd2ef63131bbcc/Libs/MRML/Logic/vtkMRMLSliceLayerLogic.cxx#L136-L160 — Slicer's 2D slice views are CPU vtkImageReslice: SetBackgroundColor(0,0,0,0), AutoCropOutputOff, SetOptimization(1), SetOutputOrigin(0,0,0), SetOutputSpacing(1,1,1), SetResliceTransform(XYToIJK) (L537-L541); labelmap volumes or Interpolate==0 force SetInterpolationModeToNearestNeighbor, otherwise linear.
- cornerstonejs/cornerstone3D — https://github.com/cornerstonejs/cornerstone3D/blob/071b8b57b8707448d1d6ec5d5f1ad28556ba9eee/packages/core/src/constants/mprCameraValues.ts — MPR_CAMERA_VALUES: axial {viewPlaneNormal:[0,0,-1], viewUp:[0,-1,0], viewRight:[1,0,0]}, sagittal {[1,0,0],[0,0,1],[0,1,0]}, coronal {[0,-1,0],[0,0,1],[1,0,0]}; viewRight = cross(viewUp, viewPlaneNormal).
- cornerstonejs/cornerstone3D — https://github.com/cornerstonejs/cornerstone3D/blob/071b8b57b8707448d1d6ec5d5f1ad28556ba9eee/packages/core/src/RenderingEngine/VolumeViewport.ts#L206-L260 — setOrientation: a named orientation resolves to {viewPlaneNormal, viewUp} from MPR_CAMERA_VALUES and is applied with setCamera({viewPlaneNormal, viewUp}); an oblique plane is just a different pair of vectors.
- cornerstonejs/cornerstone3D — https://github.com/cornerstonejs/cornerstone3D/blob/071b8b57b8707448d1d6ec5d5f1ad28556ba9eee/packages/tools/src/tools/CrosshairsTool.ts#L2351-L2380 — Rotation handle drag: rotationAxis = viewPlaneNormal of the dragged viewport; matrix = vtkMatrixBuilder.translate(center).rotate(angle, rotationAxis).translate(-center); other viewports' focalPoint/position/viewUp are transformed by it and setCamera is called.
- cornerstonejs/cornerstone3D — https://github.com/cornerstonejs/cornerstone3D/blob/071b8b57b8707448d1d6ec5d5f1ad28556ba9eee/packages/tools/src/tools/ReferenceLinesTool.ts#L90-L262 — Reference line: corners of the source viewport image in world via getViewportImageCornersInWorld; return early if isParallel(viewPlaneNormal, sourceViewPlaneNormal) (|dot| > 1-EPS); targetViewportPlane = planeEquation(normal, focalPoint); choose edge pairs pointSet1=[TL,BL,TR,BR] or pointSet2=[TL,TR,BL,BR] by isPerpendicular(topBottomVec, viewPlaneNormal); lineStart/End = linePlaneIntersection(edgeA, edgeB, plane); worldToCanvas; drawLineSvg.
- cornerstonejs/cornerstone3D — https://github.com/cornerstonejs/cornerstone3D/blob/071b8b57b8707448d1d6ec5d5f1ad28556ba9eee/packages/core/src/utilities/planar.ts#L14-L50 — linePlaneIntersection(p0,p1,[A,B,C,D]): t = -(A x0 + B y0 + C z0 - D)/(A a + B b + C c); planeEquation(normal, point) = [A,B,C, dot(normal,point)].
- cornerstonejs/cornerstone3D — https://github.com/cornerstonejs/cornerstone3D/blob/071b8b57b8707448d1d6ec5d5f1ad28556ba9eee/packages/core/src/utilities/getViewportImageCornersInWorld.ts — Returns [topLeft, topRight, bottomLeft, bottomRight] of the displayed image in world, clamped to the image bounds via indexToWorld([0,0,0]), ([dimX-1,0,0]) etc.
- cornerstonejs/cornerstone3D — https://github.com/cornerstonejs/cornerstone3D/blob/071b8b57b8707448d1d6ec5d5f1ad28556ba9eee/packages/core/src/RenderingEngine/GenericViewport/Planar/PlanarCPUVolumeSampler.ts#L155-L168 — worldVectorToContinuousIndexDelta: [dot(v,row)/spacing[0], dot(v,col)/spacing[1], dot(v,scan)/spacing[2]] — converts a world step vector to a voxel-index step vector once.
- cornerstonejs/cornerstone3D — https://github.com/cornerstonejs/cornerstone3D/blob/071b8b57b8707448d1d6ec5d5f1ad28556ba9eee/packages/core/src/RenderingEngine/GenericViewport/Planar/PlanarCPUVolumeSampler.ts#L585-L682 — CPU oblique sampler loop: xStart = -worldWidth/2 + xStep/2, yStart = worldHeight/2 - yStep/2 (pixel-centre sampling); centerIndex = worldToIndexContinuous(focalPoint); rowStartIndex = centerIndex + delta(right*xStart + up*yStart); xStepIndexDelta = delta(right*xStep); yStepIndexDelta = delta(-up*yStep); nested y/x loop adds deltas per pixel and per row.
- cornerstonejs/cornerstone3D — https://github.com/cornerstonejs/cornerstone3D/blob/071b8b57b8707448d1d6ec5d5f1ad28556ba9eee/packages/core/src/RenderingEngine/GenericViewport/Planar/PlanarCPUVolumeSampler.ts#L921-L1025 — sampleNearest: i = floor(idx + 0.5 - 1e-6), out of range -> default sample; sampleLinear: reject if outside [0, dim-1]; i0=floor, i1=min(i0+1, dim-1); di/dj/dk fractions; c00..c11 lerps along i, then j, then k.
- Kitware/vtk-js — https://github.com/Kitware/vtk-js/blob/5894d98b5f3c98c1f607fab20913fb865f5ca0dd/Sources/Imaging/Core/ImageReslice/index.js#L742-L760 — getIndexMatrix in JS: transform = resliceAxes; transform *= output.getIndexToWorld(); transform = input.getWorldToIndex() * transform — same composition as VTK, readable form; per-pixel inPoint2 = inPoint1 + idX*xAxis at L494.
- Kitware/vtk-js — https://github.com/Kitware/vtk-js/blob/5894d98b5f3c98c1f607fab20913fb865f5ca0dd/Sources/Imaging/Core/ImageInterpolator/index.js#L450-L470 — 'do full trilinear interpolation': outPtr = rx*(ryrz*in[t0+i00] + ryfz*in[t0+i01] + fyrz*in[t0+i10] + fyfz*in[t0+i11]) + fx*(... t1 ...), identical weights to VTK C++.
- Kitware/vtk-js — https://github.com/Kitware/vtk-js/blob/5894d98b5f3c98c1f607fab20913fb865f5ca0dd/Sources/Rendering/OpenGL/ImageResliceMapper/index.js#L255-L272 — GPU reslice path (what Cornerstone3D uses for rendering): the 3D texture's min/mag filter is set LINEAR or NEAREST from the property's interpolationType; fragment shader samples 'texture(volumeTexture[0], tc0)' with tc = WCTCMatrix * worldPos (L1549); slice quad geometry from computeObliqueSliceGeometryData (cutter + line-to-surface) at L1881.
- thalesmms/mtk (Metal-native medical volume rendering, Swift Package) — https://github.com/thalesmms/mtk/blob/19a5b5c263b7496a33e4981db268a6bc57e508fd/Sources/MTKCore/Resources/MPR/mpr_slab_compute.metal — Full Metal compute kernel for oblique MPR: struct MPRSlabUniforms {voxelMin/Max, blendMode, numSteps, slabHalf, slabSpan, invStepsMinusOne, float3 planeNormal, planeOrigin, planeX, planeY}; u = gid.x/(w-1), v = gid.y/(h-1); planePosition = planeOrigin + u*planeX + v*planeY (normalized texture coords); isInBounds check -> write 0; volume.sample(sampler3d, pos).r or nearest read under MTK_MPR_INTEGER_TEXTURE_READ; slab loop offset = (i*inv - 0.5)*slabSpan along planeNormal; MIP/MinIP/mean; output.write(short4(hu,hu,hu,0), gid).
- thalesmms/mtk — https://github.com/thalesmms/mtk/blob/19a5b5c263b7496a33e4981db268a6bc57e508fd/Sources/MTKCore/Resources/Shaders/volume_shader_common.metal#L8-L14 — constexpr sampler sampler3d(coord::normalized, filter::nearest, address::clamp_to_edge) used with texture3d<short>; a separate getDensityTrilinear(texture3d<float>, sampler linearSampler, ...) exists at L203 — i.e. the integer (r16Sint) volume texture is sampled nearest and trilinear needs a float-format texture.
- thalesmms/mtk — https://github.com/thalesmms/mtk/blob/19a5b5c263b7496a33e4981db268a6bc57e508fd/Sources/MTKCore/Adapters/MetalMPRComputeAdapter.swift#L430-L600 — Swift mirror of MPRSlabUniforms with layout asserts (size 132, stride 144, planeX offset 80, planeY 112); createUniforms fills planeOrigin/planeX/planeY from plane.originTexture/axisUTexture/axisVTexture; dispatch: setTexture(volume,0), setTexture(output,1), setBytes(&uniforms), threadsPerThreadgroup = ThreadgroupDispatchConfiguration.default(for: pipeline), threadsPerGrid = (width, height, 1).
- thalesmms/mtk — https://github.com/thalesmms/mtk/blob/19a5b5c263b7496a33e4981db268a6bc57e508fd/Sources/MTKCore/Geometry/MPRPlaneGeometryFactory.swift#L11-L70 — MPRPlaneGeometry = originVoxel/axisUVoxel/axisVVoxel + originWorld/axisUWorld/axisVWorld + originTexture/axisUTexture/axisVTexture + normalWorld; axial: origin (0,0,k), U=(spanX,0,0), V=(0,spanY,0); normal = normalized(cross(U,V), fallback); axes are full-extent vectors (not unit) because the kernel uses u,v in [0,1].
- thalesmms/mtk — https://github.com/thalesmms/mtk/blob/19a5b5c263b7496a33e4981db268a6bc57e508fd/Sources/MTKCore/Metal/VolumeTextureFactory.swift#L445-L462 — makeVolumeTextureDescriptor: MTLTextureDescriptor textureType .type3D, pixelFormat from dataset (r16Sint/r16Uint), usage .shaderRead, width/height/depth, storageMode .private (uploads staged through shared buffers; sync path uses texture.replace(region: MTLRegionMake3D(...), bytesPerRow, bytesPerImage) at L221).
- thalesmms/mtk — https://github.com/thalesmms/mtk/blob/19a5b5c263b7496a33e4981db268a6bc57e508fd/Sources/MTKCore/Rendering/ThreadgroupDispatchConfiguration.swift#L42-L51 — default threadgroup = (threadExecutionWidth, maxTotalThreadsPerThreadgroup / threadExecutionWidth, 1), clamped to 1024; candidate presets 8x8, 16x8, 16x16, 32x4.
- jnheo-md/open-dicom-viewer (SwiftUI DICOM viewer) — https://github.com/jnheo-md/open-dicom-viewer/blob/4a2de40b12b8be9118b44d704ae5bf72740e3451/Sources/OpenDicomViewer/VolumeData.swift#L22-L165 — Swift volume model: voxels UnsafeMutableBufferPointer<Int16>, index z*(w*h) + y*w + x; voxelToWorldMatrix columns = [rowDir*spacingX, colDir*spacingY, sliceDir*spacingZ, origin]; worldToVoxel = inverse; sampleTrilinear(vx,vy,vz): floor, fx/fy/fz, 8 voxelAt taps (out-of-bounds -> 0), lerp x then y then z.
- jnheo-md/open-dicom-viewer — https://github.com/jnheo-md/open-dicom-viewer/blob/4a2de40b12b8be9118b44d704ae5bf72740e3451/Sources/OpenDicomViewer/MPREngine.swift#L441-L475 — obliqueSlice(origin, rowDir, colDir, width, height, spacing): worldPt = origin + col*spacing*rowDir + row*spacing*colDir; voxel = worldToVoxel(worldPt); sampleTrilinear; writes Int16 into Data; renderSlice then window/levels into a CGContext(bitsPerComponent 8) and makeImage(). Serial CPU, no vImage.
- jnheo-md/open-dicom-viewer — https://github.com/jnheo-md/open-dicom-viewer/blob/4a2de40b12b8be9118b44d704ae5bf72740e3451/Sources/OpenDicomViewer/MetalVolumeRenderer.swift — Metal path (read via WebFetch summary of the raw file): inline MSL 'mip_kernel'; volume MTLTextureDescriptor .type3D .r16Sint uploaded slice-by-slice with replace(region:...); voxel read with volume.read(ushort3(clamp(int3(pos+0.5)))) i.e. nearest, no sampler; threadsPerGroup 8x8, threadgroups ceil(w/8) x ceil(h/8); output .rgba8Unorm -> getBytes -> CGContext -> CGImage.

## Recommendations
- Represent the cut as a Slicer-style SliceToWorld 4x4 whose columns are [u, v, n, origin] (unit in-plane x, unit in-plane y, unit normal, world origin) — the same shape as VTK vtkImageReslice::ResliceAxes (vtkImageReslice.h L75-L99) and vtkMRMLSliceNode::SliceToRAS. Store it in Swift as a struct {anchor, u, v, n, offset, fovMM} rather than a raw simd_float4x4 so the anchor stays explicit.
- Derive u and v from a normal plus an up hint exactly as Slicer SetSliceToRASByNTP (vtkMRMLSliceNode.cxx L655) and Cornerstone MPR_CAMERA_VALUES do: right = normalize(cross(upHint, n)); up = normalize(cross(n, right)); n = normalize(n). Fall back to a fixed axis if the hint is parallel to n (mtk MPRPlaneGeometryFactory 'normalized(vector:fallback:)').
- Use the standard presets as literal vectors: axial n=(0,0,1) with screen-up = anterior (0,1,0); coronal n=(0,-1,0) with screen-up = superior (0,0,1) — these are Cornerstone's coronal viewPlaneNormal/viewUp and Slicer's Coronal matrix columns. Our hinge tilt is then a rotation of the axial basis about the patient left-right axis x̂ by tilt = clamp(180 - deviceAngle, 0, 90) (the mapping itself is the PRD's, not a precedent), which lands exactly on the coronal preset at 90°.
- Express 'rotate the cut about the selected finding' as Slicer vtkMRMLSliceIntersectionWidget::Rotate (L1154) / Cornerstone CrosshairsTool (L2351): M' = T(anchor) · R(axis, θ) · T(-anchor) · M. In practice: rotate u, v, n with simd_quatf(angle:axis:) and keep anchor untouched; the anchor is the pivot so the finding never leaves the slice.
- Express the drag-to-translate control as Slicer SetSliceOffset / JumpSliceByOffsetting (vtkMRMLSliceNode.cxx L1298, L1761): a scalar offset along n; center = anchor + offset*n. Reset offset to 0 when a new finding is selected (Slicer JumpSlice on click).
- Map output pixels to world the Slicer/Cornerstone way: pixel (0,0) is the top-left corner, the plane centre sits at -FOV/2 (vtkMRMLSliceNode::UpdateMatrices L752), sample at pixel centres (Cornerstone PlanarCPUVolumeSampler L585: xStart = -w/2 + step/2, yStart = +h/2 - step/2) and step rows in -v because screen y grows downward (Cornerstone yStepIndexDelta uses -up).
- Do the inner loop in continuous voxel-index space with constant per-pixel and per-row deltas, never a per-pixel matrix multiply: VTK vtkImageResliceExecute (L636-L694: point = origin + idZ*zAxis + idY*yAxis + idX*xAxis) and Cornerstone worldVectorToContinuousIndexDelta (L155). World->index for an axis-aligned volume is (p - origin)/spacing (VTK GetIndexMatrix inMatrix).
- Sample HU with VTK's Trilinear (vtkImageInterpolator.cxx L200): floor, fx/fy/fz, second index = first + (f != 0), clamp both to [0, dim-1], weights rx*ryrz..., 8 taps via precomputed row/slab strides. Sample the tissue-label volume with nearest neighbour (VTK Nearest L158 = round then clamp; Cornerstone uses floor(i + 0.5 - 1e-6)); Slicer vtkMRMLSliceLayerLogic forces NearestNeighbor for labelmap volumes for exactly this reason (label averaging produces nonsense classes).
- Ship the CPU sampler first: fill a reusable width*height*4 UInt8 buffer with DispatchQueue.concurrentPerform over rows and wrap it in a CGImage via CGDataProvider (open-dicom-viewer MPREngine.obliqueSlice + renderSlice, Cornerstone PlanarCPUVolumeSampler, Slicer's own 2D views are CPU vtkImageReslice with SetOptimization(1)). At 256x256 this is ~65k trilinear samples per frame — roughly 2-4 ms single-core in -O Swift with unsafe pointers, under 1 ms across cores, against a 16.7 ms budget.
- Shape the plane parameters as mtk's MPRSlabUniforms (planeOrigin, planeX, planeY, planeNormal in normalized texture space) so the GPU upgrade is a drop-in: copy mpr_slab_compute.metal (u = gid.x/(w-1), planePosition = planeOrigin + u*planeX + v*planeY, isInBounds -> 0, output.write) with a .type3D texture from VolumeTextureFactory.makeVolumeTextureDescriptor and threadgroups from ThreadgroupDispatchConfiguration.default. Only switch when profiling shows >8 ms per frame (e.g. 512x512 output or multi-sample slabs).
- If the GPU path is taken, upload HU as .r16Float or .r16Snorm (scaled), not .r16Sint: mtk's sampler3d for its texture3d<short> is filter::nearest and its trilinear helper takes texture3d<float>; open-dicom-viewer also does nearest volume.read on r16Sint. Integer Metal textures cannot be linearly filtered by the sampler.
- Treat pixels whose continuous index falls outside [0, dim-1] as fully transparent (Slicer vtkMRMLSliceLayerLogic SetBackgroundColor(0,0,0,0); Cornerstone sampleLinear returns the default sample; mtk isInBounds -> write 0) so the body silhouette shows against the app background.
- Draw the cut on the overview with Slicer's IntersectWithFinitePlane (vtkMRMLSliceIntersectionRepresentation2D.cxx L231): take the cut rectangle's corners o, o+U, o+V, o+U+V in world, intersect the four edges with the overview plane (Cornerstone linePlaneIntersection: t = dot(n, p0 - a)/dot(n, b - a), accept 0..1), stop at two hits, project the two hits into overview pixels with the overview's own [u, v] basis (Slicer rasToXY = inverse XYToRAS), and skip drawing when |dot(n_overview, n_cut)| > 1 - 1e-5 (Cornerstone ReferenceLinesTool isParallel early return).
- Choose the overview orientation so the tilt is visible: because the hinge rotates the cut about the patient left-right axis, on a coronal (front) overview the cut line stays horizontal and only slides; on a sagittal (side) overview it rotates about the finding marker. Give the bottom-half overview a side-profile mini-map (or a 3D-ish parallelogram like Slicer's 3D-view slice plane) so the hinge motion reads on stage.
- Colour the cut line with the finding/cut's accent colour and give it a draggable handle at its midpoint, following Slicer (Property->SetColor(GetLayoutColor()), SetLineWidth) and Cornerstone (drawLineSvg with color/width/lineDash); the drag updates the scalar offset only, the hinge updates the tilt only, so the two gestures never fight (PRD requirement).

## Concrete values
## 1. Plane parameterization (copy of Slicer SliceToRAS / VTK ResliceAxes)

```
SliceToWorld (4x4, column-major) =
   | u.x  v.x  n.x  o.x |      u = in-plane x unit (screen right)
   | u.y  v.y  n.y  o.y |      v = in-plane y unit (screen up)
   | u.z  v.z  n.z  o.z |      n = unit normal = cross(u, v)
   |  0    0    0    1  |      o = plane origin (centre of the field of view), world mm
```
World frame for the synthetic body (RAS-like, matches Slicer/Cornerstone constants): +x = patient left→right axis (L-R), +y = anterior, +z = superior. Voxel index (i,j,k) ↔ world: `world = origin + (i,j,k) * spacing` (VTK outMatrix/inMatrix with identity direction).

Building (u, v) from a normal + up hint — Slicer `SetSliceToRASByNTP` (c = n×t, t = c×n) / Cornerstone (viewRight = viewUp × viewPlaneNormal):
```
n     = normalize(n)
right = normalize(cross(upHint, n))     // if |cross| < 1e-4: upHint ∥ n → use cross((1,0,0), n)
up    = normalize(cross(n, right))
u = right, v = up
```

Presets (Cornerstone `mprCameraValues.ts`, Slicer `Get*SliceToRASMatrix`):
| preset   | n (normal)  | v (screen up) | u = cross(v, n) |
|----------|-------------|---------------|-----------------|
| axial    | (0, 0, 1)   | (0, 1, 0) A   | (1, 0, 0)       |
| coronal  | (0, -1, 0)  | (0, 0, 1) S   | (1, 0, 0)       |
| sagittal | (1, 0, 0)   | (0, 0, 1) S   | (0, 1, 0)       |
(Cornerstone's axial uses n = (0,0,-1), up = (0,-1,0) because its camera looks *along* -n; the plane is the same. Slicer flips u to (-1,0,0) for radiological "patient right on screen left" — pick one and keep the overview consistent.)

Rotation about the finding (Slicer `vtkMRMLSliceIntersectionWidget::Rotate`, Cornerstone `CrosshairsTool` matrix builder):
```
R      = T(anchor) · Rot(axis = (1,0,0), θ) · T(-anchor)
M'     = R · M                       // Slicer: Multiply4x4(rotated, SliceToRAS)
in vectors: u' = q.act(u), v' = q.act(v), n' = q.act(n), anchor unchanged
q      = simd_quatf(angle: θ·π/180, axis: (1,0,0))
```
Hinge mapping (PRD, not a precedent): `tiltDeg = clamp(180 - deviceAngleDeg, 0, 90)`; θ=0 → axial n=(0,0,1); θ=90 → n=(0,-1,0)=coronal, v=(0,0,1). Slicer multiplies the angle by `sign(det(rotation part))` — keep the basis right-handed (n = cross(u,v)) or the hinge direction flips.

Translation (Slicer `JumpSliceByOffsetting` / `SetSliceOffset`): `center = anchor + offset · n`; drag-to-point: `offset = dot(p - anchor, n)`.

Output pixel → world (Slicer `UpdateMatrices`: -FOV/2; Cornerstone: pixel-centre, rows go down):
```
sx = fovMM.x / W,  sy = fovMM.y / H
topLeft = center + u·(-fovMM.x/2 + sx/2) + v·(fovMM.y/2 - sy/2)
world(col,row) = topLeft + col·sx·u - row·sy·v
```

## 2. Sampling / index math

World → continuous index (VTK `GetIndexMatrix` inMatrix, identity direction): `idx = (world - volumeOrigin) / spacing` (componentwise).

Per-frame constants (VTK xAxis/yAxis; Cornerstone xStepIndexDelta/yStepIndexDelta):
```
rowStart0 = (topLeft - volumeOrigin) / spacing
dx        = ( u · sx) / spacing          // index delta per column
dy        = (-v · sy) / spacing          // index delta per row
p(col,row) = rowStart0 + row·dy + col·dx
```

Trilinear (VTK `vtkImageNLCInterpolate::Trilinear`, strides incX=1, incY=nx, incZ=nx·ny):
```
x0 = floor(px); fx = px - x0;  x1 = x0 + (fx != 0 ? 1 : 0)   // same for y,z
clamp x0,x1 to [0,nx-1]; y0,y1 to [0,ny-1]; z0,z1 to [0,nz-1]
i00 = y0·nx + z0·nx·ny;  i01 = y0·nx + z1·nx·ny;  i10 = y1·nx + z0·nx·ny;  i11 = y1·nx + z1·nx·ny
rx=1-fx ry=1-fy rz=1-fz;  ryrz=ry·rz fyrz=fy·rz ryfz=ry·fz fyfz=fy·fz
p0 = base + x0; p1 = base + x1
value = rx·(ryrz·p0[i00] + ryfz·p0[i01] + fyrz·p0[i10] + fyfz·p0[i11])
      + fx·(ryrz·p1[i00] + ryfz·p1[i01] + fyrz·p1[i10] + fyfz·p1[i11])
```
Nearest (VTK `Nearest`: Round then Clamp; Cornerstone: `floor(i + 0.5 - 1e-6)`): `i = clamp(Int(floor(px + 0.5 - 1e-6)), 0, nx-1)`; `label = labels[i + nx·(j + ny·k)]`.

Bounds: outside `[0, dim-1]` on any axis → transparent pixel (Slicer background (0,0,0,0); Cornerstone default sample; mtk isInBounds → 0). Use trilinear for HU (`Int16`), nearest for tissue labels (`UInt8`) — Slicer forces NearestNeighbor for labelmaps.

## 3. CPU vs Metal for 256×256 @ 60 fps

| | CPU → CGImage | Metal compute → MTLTexture |
|---|---|---|
| Precedent | open-dicom-viewer `MPREngine.obliqueSlice`; Cornerstone `PlanarCPUVolumeSampler`; Slicer 2D views = `vtkImageReslice` CPU | thalesmms/mtk `mpr_slab_compute.metal`; Cornerstone/vtk.js `OpenGLImageResliceMapper` (GPU 3D texture) |
| Work per frame | 65,536 px × (8 Int16 taps + 1 UInt8 tap + ~20 flops) ≈ 2–4 ms single core (-O, unsafe pointers); ≈ 0.5–1 ms with `concurrentPerform` over rows | ~0.1 ms GPU; plus command-buffer latency ~1 ms |
| Memory | 256³ Int16 = 32 MB + labels 16 MB, random oblique access but tiny sample count | same data as `.type3D` texture (`.r16Float` 32 MB) |
| Risk today | none beyond keeping work off main thread; deterministic in simulator | `.metal` files must compile in the Bitrig target; integer textures can't be linearly filtered (mtk `sampler3d` is `filter::nearest` on `texture3d<short>`); readback via `getBytes` if you still want a CGImage |
| Verdict | **Use now.** Budget 16.7 ms; we use <2 ms. | Switch only if profiling shows >8 ms (512×512 output, ≥4-sample slabs, two volumes). Keep the plane struct in mtk's `MPRSlabUniforms` layout so it is a drop-in. |

mtk dispatch shape if/when needed: `threadsPerThreadgroup = (threadExecutionWidth, maxTotalThreadsPerThreadgroup / threadExecutionWidth, 1)`, `threadsPerGrid = (W, H, 1)`; open-dicom-viewer uses 8×8 and `dispatchThreadgroups(ceil(W/8), ceil(H/8))`. Volume texture: `MTLTextureDescriptor.textureType = .type3D`, `pixelFormat = .r16Float` (not `.r16Sint` if you want `filter::linear`), `usage = .shaderRead`, upload with `replace(region: MTLRegionMake3D(0,0,0,nx,ny,nz), mipmapLevel: 0, slice: 0, withBytes:, bytesPerRow: nx*2, bytesPerImage: nx*ny*2)`.

## 4. Cut line on the overview (Slicer IntersectWithFinitePlane + Cornerstone ReferenceLines)

```
// cut rectangle corners in world (Cornerstone getViewportImageCornersInWorld / Slicer intersectingPlaneOrigin, X, Y)
c = cut.center;  hu = cut.u · fov.x/2;  hv = cut.v · fov.y/2
o = c - hu - hv;  px = c + hu - hv;  py = c - hu + hv;  pxy = c + hu + hv
// Cornerstone isParallel early-out
if |dot(ov.n, cut.n)| > 1 - 1e-5 → no line
// Slicer edge order: o→px, o→py, pxy→py, pxy→px; stop at 2 hits
segment∩plane(a,b): t = dot(ov.n, ov.center - a) / dot(ov.n, b - a); hit iff denom≠0 and 0≤t≤1; x = a + t·(b-a)
// world → overview pixels (Slicer rasToXY)
d = x - ov.center;  px = ovW/2 + dot(d, ov.u)·pxPerMM;  py = ovH/2 - dot(d, ov.v)·pxPerMM
```
Overview choice: with tilt axis = (1,0,0), a sagittal overview (n=(1,0,0), u=(0,1,0), v=(0,0,1)) shows the line rotating about the marker: for tilt θ the line direction in overview pixels is (cos θ, sin θ) through the anchor. A coronal overview shows a horizontal line that only translates.

## 5. Swift pseudo-code

```swift
import simd, CoreGraphics, Dispatch

struct Volume {                     // open-dicom-viewer VolumeData + VTK inMatrix
    let dims: SIMD3<Int>            // nx, ny, nz
    let spacing: SIMD3<Float>       // mm
    let origin: SIMD3<Float>        // world of voxel (0,0,0) centre
    let hu: UnsafeBufferPointer<Int16>     // x + nx*(y + ny*z)
    let labels: UnsafeBufferPointer<UInt8> // same layout, tissue class
    @inline(__always) func toIndex(_ p: SIMD3<Float>) -> SIMD3<Float> { (p - origin) / spacing }
}

struct CutPlane {                   // Slicer SliceToRAS columns [u, v, n, origin]
    var anchor: SIMD3<Float>        // selected finding, world mm — rotation pivot
    var u, v, n: SIMD3<Float>       // unit; n = cross(u, v)
    var offset: Float = 0           // Slicer SetSliceOffset: along n
    var fovMM: SIMD2<Float>
    var center: SIMD3<Float> { anchor + offset * n }

    static func from(normal: SIMD3<Float>, upHint: SIMD3<Float>, anchor: SIMD3<Float>, fovMM: SIMD2<Float>) -> CutPlane {
        let n = simd_normalize(normal)                          // Slicer SetSliceToRASByNTP / Cornerstone viewRight
        var r = simd_cross(upHint, n)
        if simd_length_squared(r) < 1e-8 { r = simd_cross(SIMD3(1,0,0), n) }
        r = simd_normalize(r)
        return CutPlane(anchor: anchor, u: r, v: simd_normalize(simd_cross(n, r)), n: n, offset: 0, fovMM: fovMM)
    }
    /// Hinge: rotate the axial basis about the patient L-R axis through the anchor
    /// (Slicer vtkMRMLSliceIntersectionWidget::Rotate = T(c)·R·T(-c), applied to the basis only).
    static func tilted(degrees: Float, anchor: SIMD3<Float>, fovMM: SIMD2<Float>) -> CutPlane {
        let q = simd_quatf(angle: degrees * .pi / 180, axis: SIMD3(1, 0, 0))
        return from(normal: q.act(SIMD3(0,0,1)), upHint: q.act(SIMD3(0,1,0)), anchor: anchor, fovMM: fovMM)
    }
}

final class CrossSectionSampler {
    let vol: Volume; let W: Int; let H: Int
    var rgba: UnsafeMutableBufferPointer<UInt8>   // W*H*4, double-buffer between frames
    var lut: [SIMD4<UInt8>]                       // tissue class → colour
    var visible: [Bool]                           // peeled layers → false
    var showCT = false; var wl: (center: Float, width: Float) = (40, 400)

    func fill(plane: CutPlane, translationMM: Float) {
        var p = plane; p.offset = translationMM
        let sx = p.fovMM.x / Float(W), sy = p.fovMM.y / Float(H)
        let topLeft = p.center + p.u * (-p.fovMM.x/2 + sx/2) + p.v * (p.fovMM.y/2 - sy/2)  // Slicer -FOV/2, Cornerstone pixel centre
        let row0 = vol.toIndex(topLeft)                                                     // VTK: index space once
        let dx = (p.u * sx) / vol.spacing                                                   // Cornerstone xStepIndexDelta
        let dy = (-p.v * sy) / vol.spacing                                                  // yStepIndexDelta (rows go down)
        let nx = vol.dims.x, ny = vol.dims.y, nz = vol.dims.z
        let maxI = SIMD3<Float>(Float(nx-1), Float(ny-1), Float(nz-1))
        DispatchQueue.concurrentPerform(iterations: H) { row in
            var q = row0 + Float(row) * dy
            var o = row * W * 4
            for _ in 0..<W {
                var px = SIMD4<UInt8>(0,0,0,0)
                if all(q .>= 0) && all(q .<= maxI) {                       // Slicer background (0,0,0,0) outside
                    let label = nearest(q)                                // VTK Nearest / Slicer labelmap rule
                    if showCT {
                        let h = trilinear(q)                              // VTK Trilinear
                        let g = UInt8(clamping: Int(((h - (wl.center - wl.width/2)) / wl.width * 255).rounded()))
                        px = SIMD4(g, g, g, 255)
                    } else if visible[Int(label)] { px = lut[Int(label)] }
                }
                rgba[o] = px.x; rgba[o+1] = px.y; rgba[o+2] = px.z; rgba[o+3] = px.w
                o += 4; q += dx                                            // VTK inPoint2 = inPoint1 + idX*xAxis
            }
        }
    }

    @inline(__always) func trilinear(_ q: SIMD3<Float>) -> Float {         // vtkImageNLCInterpolate::Trilinear
        let f = floor(q); let fx = q.x - f.x, fy = q.y - f.y, fz = q.z - f.z
        let nx = vol.dims.x, ny = vol.dims.y, nz = vol.dims.z
        let x0 = min(max(Int(f.x), 0), nx-1), x1 = min(x0 + (fx != 0 ? 1 : 0), nx-1)
        let y0 = min(max(Int(f.y), 0), ny-1), y1 = min(y0 + (fy != 0 ? 1 : 0), ny-1)
        let z0 = min(max(Int(f.z), 0), nz-1), z1 = min(z0 + (fz != 0 ? 1 : 0), nz-1)
        let incY = nx, incZ = nx*ny
        let i00 = y0*incY + z0*incZ, i01 = y0*incY + z1*incZ, i10 = y1*incY + z0*incZ, i11 = y1*incY + z1*incZ
        let rx = 1-fx, ry = 1-fy, rz = 1-fz
        let ryrz = ry*rz, fyrz = fy*rz, ryfz = ry*fz, fyfz = fy*fz
        let p0 = vol.hu.baseAddress! + x0, p1 = vol.hu.baseAddress! + x1
        return rx * (ryrz*Float(p0[i00]) + ryfz*Float(p0[i01]) + fyrz*Float(p0[i10]) + fyfz*Float(p0[i11]))
             + fx * (ryrz*Float(p1[i00]) + ryfz*Float(p1[i01]) + fyrz*Float(p1[i10]) + fyfz*Float(p1[i11]))
    }
    @inline(__always) func nearest(_ q: SIMD3<Float>) -> UInt8 {           // VTK Nearest / Cornerstone floor(i+0.5-1e-6)
        let i = min(max(Int((q.x + 0.5 - 1e-6).rounded(.down)), 0), vol.dims.x-1)
        let j = min(max(Int((q.y + 0.5 - 1e-6).rounded(.down)), 0), vol.dims.y-1)
        let k = min(max(Int((q.z + 0.5 - 1e-6).rounded(.down)), 0), vol.dims.z-1)
        return vol.labels[i + vol.dims.x * (j + vol.dims.y * k)]
    }

    func makeImage() -> CGImage? {                                          // open-dicom-viewer renderSlice → CGContext/makeImage; zero-copy variant
        guard let provider = CGDataProvider(dataInfo: nil, data: rgba.baseAddress!, size: rgba.count, releaseData: { _,_,_ in }) else { return nil }
        return CGImage(width: W, height: H, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: W*4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// Overview cut line — Slicer IntersectWithFinitePlane + Cornerstone linePlaneIntersection/isParallel
func cutLine(on ov: CutPlane, cut: CutPlane, ovSize: CGSize, pxPerMM: CGFloat) -> (CGPoint, CGPoint)? {
    if abs(simd_dot(ov.n, cut.n)) > 1 - 1e-5 { return nil }
    let c = cut.center, hu = cut.u * cut.fovMM.x/2, hv = cut.v * cut.fovMM.y/2
    let o = c - hu - hv, px = c + hu - hv, py = c - hu + hv, pxy = c + hu + hv
    var hits: [SIMD3<Float>] = []
    for (a, b) in [(o, px), (o, py), (pxy, py), (pxy, px)] {
        let den = simd_dot(ov.n, b - a); if abs(den) < 1e-6 { continue }
        let t = simd_dot(ov.n, ov.center - a) / den
        if t >= 0 && t <= 1 { hits.append(a + t * (b - a)); if hits.count == 2 { break } }
    }
    guard hits.count == 2 else { return nil }
    func toPx(_ w: SIMD3<Float>) -> CGPoint {
        let d = w - ov.center
        return CGPoint(x: ovSize.width/2 + CGFloat(simd_dot(d, ov.u)) * pxPerMM,
                       y: ovSize.height/2 - CGFloat(simd_dot(d, ov.v)) * pxPerMM)
    }
    return (toPx(hits[0]), toPx(hits[1]))
}
```

Metal drop-in (if ever needed) — mtk `MPRSlabUniforms` (size 132, stride 144; planeNormal @32, planeOrigin @48, planeX @80, planeY @112):
```
planeOrigin = toTexture(topLeft)                       // normalized [0,1]^3 = index/(dims-1) or index/dims per your sampler convention
planeX = toTexture(topLeft + u·fovMM.x) - planeOrigin  // full-extent vectors, kernel does u = gid.x/(W-1)
planeY = toTexture(topLeft - v·fovMM.y) - planeOrigin
kernel: pos = planeOrigin + u*planeX + v*planeY; if !all(pos in [-1e-6, 1+1e-6]) write 0; volume.sample(sampler(filter::linear, address::clamp_to_edge), pos)
```

## Risks
- Integer Metal textures (.r16Sint/.r16Uint) cannot be sampled with filter::linear — mtk's own sampler3d is filter::nearest for texture3d<short> and its trilinear helper takes texture3d<float>. If the GPU path is adopted, upload HU as .r16Float (or scaled .r16Snorm) or do the 8-tap trilinear manually in the kernel.
- A front (coronal) overview hides the hinge: because the tilt axis is the patient L-R axis, the cut line on a coronal overview stays horizontal and only slides. Use a sagittal side-profile mini-map for the cut line, or the line will look broken on stage.
- Pixel-centre vs pixel-corner conventions differ between precedents (Cornerstone samples at centres: -w/2 + step/2; VTK/Slicer at index positions with -FOV/2). Mixing them between the slice sampler and the overview cut line gives a half-pixel offset of the finding marker.
- Screen rows grow downward: the row step must be -v (Cornerstone yStepIndexDelta = delta(-up)); forgetting the sign mirrors the slice top-to-bottom relative to the overview.
- Handedness: Slicer multiplies the rotation angle by sign(det(SliceToRAS)). If u,v,n are not kept right-handed (n = cross(u,v)), the hinge tilts the cut the wrong way.
- The rotation must be applied to the basis vectors with the anchor as pivot; if the plane origin is rotated instead (or offset is not reset when a new finding is selected — Slicer JumpSlice resets), the finding drifts off the slice as the hinge moves.
- CPU path threading: the RGBA buffer wrapped in a CGDataProvider is read lazily by CoreGraphics; writing the next frame into the same buffer while the previous CGImage is still being drawn tears. Double-buffer and coalesce hinge updates (drop frames, never queue them).
- Slabs multiply cost linearly (mtk numSteps loop); keep the CPU path single-sample. Slab MIP/mean or >512x512 outputs are the trigger to move to the mtk compute kernel.
- Averaging the tissue-label volume produces phantom classes at boundaries; labels must use nearest sampling (Slicer forces NearestNeighbor for labelmaps). Only HU is trilinear.
- The two Swift precedents are small projects (open-dicom-viewer 20 stars, thalesmms/mtk 5 stars); they show the Swift/Metal API shape but the load-bearing design is VTK / 3D Slicer / Cornerstone3D. OsiriX/Horos and ITK-SNAP were not opened for this research.
- The hinge-angle to tilt mapping (180° → 0°, 90° → 90°) is the PRD's demo interaction with no open-source precedent; it should stay a single clamp() line so it can be re-tuned on Duo hardware.
