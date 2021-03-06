//
//  MetalUtilities.swift
//  AugmentKit2
//
//  MIT License
//
//  Copyright (c) 2017 JamieScanlon
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//
//
//  Metal utility functions for setting up the render engine state
//

import Foundation
import MetalKit
import simd
import GLKit
import AugmentKitShader

class MetalUtilities {
    
    static func getFuncConstantsForDrawDataSet(meshData: MeshData?, useMaterials: Bool) -> MTLFunctionConstantValues {
        
        var has_base_color_map = false
        var has_normal_map = false
        var has_metallic_map = false
        var has_roughness_map = false
        var has_ambient_occlusion_map = false
        var has_irradiance_map = false

        // Condition all subdata since we only do a pipelinestate once per DrawData
        if let meshData = meshData, useMaterials {
            for material in meshData.materials {
                has_base_color_map = has_base_color_map || (material.baseColor.1 != nil)
                has_normal_map = has_normal_map || (material.normalMap != nil)
                has_metallic_map = has_metallic_map || (material.metallic.1 != nil)
                has_roughness_map = has_roughness_map || (material.roughness.1 != nil)
                has_ambient_occlusion_map = has_ambient_occlusion_map || (material.ambientOcclusionMap != nil)

                // -- currently not featured
                has_irradiance_map = false
            }
        }

        let constantValues = MTLFunctionConstantValues()
        constantValues.setConstantValue(&has_base_color_map, type: .bool, index: Int(kFunctionConstantBaseColorMapIndex.rawValue))
        constantValues.setConstantValue(&has_normal_map, type: .bool, index: Int(kFunctionConstantNormalMapIndex.rawValue))
        constantValues.setConstantValue(&has_metallic_map, type: .bool, index: Int(kFunctionConstantMetallicMapIndex.rawValue))
        constantValues.setConstantValue(&has_roughness_map, type: .bool, index: Int(kFunctionConstantRoughnessMapIndex.rawValue))
        constantValues.setConstantValue(&has_ambient_occlusion_map, type: .bool, index: Int(kFunctionConstantAmbientOcclusionMapIndex.rawValue))
        constantValues.setConstantValue(&has_irradiance_map, type: .bool, index: Int(kFunctionConstantIrradianceMapIndex.rawValue))
        return constantValues
    }
    
    static func convertToMTLIndexType(from mdlIdxBitDepth: MDLIndexBitDepth) -> MTLIndexType {
        switch mdlIdxBitDepth {
        case .uInt16:
            return .uint16
        case .uInt32:
            return .uint32
        case .uInt8:
            print("UInt8 unsupported, defaulting to uint16")
            return .uint16
        case .invalid:
            print("Invalid MTLIndexType, defaulting to uint16")
            return .uint16
        }
    }
    
    static func convertToMaterialUniform(from material: Material) -> MaterialUniforms {
        var matUniforms = MaterialUniforms()
        let baseColor = material.baseColor.0 ?? float3(1.0, 1.0, 1.0)
        matUniforms.baseColor = float4(baseColor.x, baseColor.y, baseColor.z, 1.0)
        matUniforms.roughness = material.roughness.0 ?? 1.0
        matUniforms.irradiatedColor = float4(1.0, 1.0, 1.0, 1.0)
        matUniforms.metalness = material.metallic.0 ?? 0.0
        return matUniforms
    }
    
    static func convertMaterialBuffer(from material: Material, with materialBuffer: MTLBuffer, offset: Int) {
        
        let theBuffer = materialBuffer.contents().assumingMemoryBound(to: MaterialUniforms.self).advanced(by: offset)
        let baseColor = material.baseColor.0 ?? float3(1.0, 1.0, 1.0)
        theBuffer.pointee.baseColor = float4(baseColor.x, baseColor.y, baseColor.z, 1.0)
        theBuffer.pointee.roughness = material.roughness.0 ?? 1.0
        theBuffer.pointee.irradiatedColor = float4(1.0, 1.0, 1.0, 1.0)
        theBuffer.pointee.metalness = material.metallic.0 ?? 0.0
        
    }
    
    static func isTexturedProperty(_ propertyIndex: FunctionConstantIndices, at quality: QualityLevel) -> Bool {
        var minLevelForProperty = kQualityLevelHigh
        switch propertyIndex {
        case kFunctionConstantBaseColorMapIndex:
            fallthrough
        case kFunctionConstantIrradianceMapIndex:
            minLevelForProperty = kQualityLevelMedium
        default:
            break
        }
        return quality.rawValue <= minLevelForProperty.rawValue
    }
    
}

// MARK: - float4x4

extension float4x4 {
    
    static func makeScale(x: Float, y: Float, z: Float) -> float4x4 {
        return unsafeBitCast(GLKMatrix4MakeScale(x, y, z), to: float4x4.self)
    }
    
    static func makeRotate(radians: Float, x: Float, y: Float, z: Float) -> float4x4 {
        return unsafeBitCast(GLKMatrix4MakeRotation(radians, x, y, z), to: float4x4.self)
    }
    
    static func makeTranslation(x: Float, y: Float, z: Float) -> float4x4 {
        return unsafeBitCast(GLKMatrix4MakeTranslation(x, y, z), to: float4x4.self)
    }
    
    static func makePerspective(fovyRadians: Float, aspect: Float, nearZ: Float, farZ: Float) -> float4x4 {
        return unsafeBitCast(GLKMatrix4MakePerspective(fovyRadians, aspect, nearZ, farZ), to: float4x4.self)
    }
    
    static func makeFrustum(left: Float, right: Float, bottom: Float, top: Float, nearZ: Float, farZ: Float) -> float4x4 {
        return unsafeBitCast(GLKMatrix4MakeFrustum(left, right, bottom, top, nearZ, farZ), to: float4x4.self)
    }
    
    static func makeOrtho(left: Float, right: Float, bottom: Float, top: Float, nearZ: Float, farZ: Float) -> float4x4 {
        return unsafeBitCast(GLKMatrix4MakeOrtho(left, right, bottom, top, nearZ, farZ), to: float4x4.self)
    }
    
    static func makeLookAt(eyeX: Float, eyeY: Float, eyeZ: Float, centerX: Float, centerY: Float, centerZ: Float, upX: Float, upY: Float, upZ: Float) -> float4x4 {
        return unsafeBitCast(GLKMatrix4MakeLookAt(eyeX, eyeY, eyeZ, centerX, centerY, centerZ, upX, upY, upZ), to: float4x4.self)
    }
    
    static func makeQuaternion(from: float4x4) -> GLKQuaternion {
        return GLKQuaternionMakeWithMatrix4(unsafeBitCast(from, to: GLKMatrix4.self))
    }
    
    func scale(x: Float, y: Float, z: Float) -> float4x4 {
        return self * float4x4.makeScale(x: x, y: y, z: z)
    }
    
    func rotate(radians: Float, x: Float, y: Float, z: Float) -> float4x4 {
        return self * float4x4.makeRotate(radians: radians, x: x, y: y, z: z)
    }
    
    func translate(x: Float, y: Float, z: Float) -> float4x4 {
        return self * float4x4.makeTranslation(x: x, y: y, z: z)
    }
    
    func quaternion() -> GLKQuaternion {
        return float4x4.makeQuaternion(from: self)
    }
    
}

class QuaternionUtilities {
    
    static func quaternionFromEulerAngles(pitch: Float, roll: Float, yaw: Float) -> GLKQuaternion {
        
        let cy = cos(yaw * 0.5)
        let sy = sin(yaw * 0.5)
        let cr = cos(roll * 0.5)
        let sr = sin(roll * 0.5)
        let cp = cos(pitch * 0.5)
        let sp = sin(pitch * 0.5)
        
        let w = cy * cr * cp + sy * sr * sp
        let x = cy * sr * cp - sy * cr * sp
        let y = cy * cr * sp + sy * sr * cp
        let z = sy * cr * cp - cy * sr * sp
        
        return GLKQuaternionMake(x, y, z, w)
        
    }
    
}

