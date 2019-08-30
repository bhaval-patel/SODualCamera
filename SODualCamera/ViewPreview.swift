//
//  ViewPreview.swift
//  SODualCamera
//
//  Created by SOTSYS207 on 05/08/19.
//  Copyright © 2019 SOTSYS207. All rights reserved.
//

import UIKit
import AVFoundation

class ViewPreview: UIView {
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected `AVCaptureVideoPreviewLayer` type for layer. Check PreviewView.layerClass implementation.")
        }
        
        layer.videoGravity = .resizeAspect
        return layer
    }
    
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self	
    }
}
