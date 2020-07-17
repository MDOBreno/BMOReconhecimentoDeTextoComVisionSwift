//
//  PreviewView.swift
//  BMOReconhecimentoDeTextoComVisionSwift
//
//  Created by Breno Medeiros on 09/07/20.
//  Copyright © 2020 ProgramasBMO. All rights reserved.
//
/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Application preview view
*/

import UIKit
import AVFoundation

class PreviewView: UIView {
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected `AVCaptureVideoPreviewLayer` type for layer. Check PreviewView.layerClass implementation.")
        }
        
        return layer
    }
    
    var session: AVCaptureSession? {
        get {
            return videoPreviewLayer.session
        }
        set {
            videoPreviewLayer.session = newValue
        }
    }
    
    // MARK: UIView
    
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
}
