

import UIKit
import Foundation
import AVFoundation
import ReplayKit
import Photos

extension UIApplication {

    class func getTopViewController(base: UIViewController? = UIApplication.shared.keyWindow?.rootViewController) -> UIViewController? {

        if let nav = base as? UINavigationController {
            return getTopViewController(base: nav.visibleViewController)

        } else if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return getTopViewController(base: selected)

        } else if let presented = base?.presentedViewController {
            return getTopViewController(base: presented)
        }
        return base
    }
}

class AssetWriter {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private let fileName: String
    
    let writeQueue = DispatchQueue(label: "writeQueue")
    
    init(fileName: String) {
        self.fileName = fileName
    }
    
    private var videoDirectoryPath: String {
        let dir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        return dir + "/Videos"
    }
    
    private var filePath: String {
        return videoDirectoryPath + "/\(fileName)"
    }
    
    private func setupWriter(buffer: CMSampleBuffer) {
        if FileManager.default.fileExists(atPath: videoDirectoryPath) {
            do {
                try FileManager.default.removeItem(atPath: videoDirectoryPath)
            } catch {
                print("fail to removeItem")
            }
        }
        do {
            try FileManager.default.createDirectory(atPath: videoDirectoryPath, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("fail to createDirectory")
        }
        
        self.assetWriter = try? AVAssetWriter(outputURL: URL(fileURLWithPath: filePath), fileType: AVFileType.mov)
        
        let writerOutputSettings = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: UIScreen.main.bounds.width,
            AVVideoHeightKey: UIScreen.main.bounds.height,
            ] as [String : Any]
        
        self.videoInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: writerOutputSettings)
        self.videoInput?.expectsMediaDataInRealTime = true
        
        guard let format = CMSampleBufferGetFormatDescription(buffer),
            let stream = CMAudioFormatDescriptionGetStreamBasicDescription(format) else {
                print("fail to setup audioInput")
                return
        }
        
        let audioOutputSettings = [
            AVFormatIDKey : kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey : stream.pointee.mChannelsPerFrame,
            AVSampleRateKey : stream.pointee.mSampleRate,
            AVEncoderBitRateKey : 64000
            ] as [String : Any]
        
        self.audioInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioOutputSettings)
        self.audioInput?.expectsMediaDataInRealTime = true
        
        if let videoInput = self.videoInput, (self.assetWriter?.canAdd(videoInput))! {
            self.assetWriter?.add(videoInput)
        }
        
        if  let audioInput = self.audioInput, (self.assetWriter?.canAdd(audioInput))! {
            self.assetWriter?.add(audioInput)
        }
    }
    
    public func write(buffer: CMSampleBuffer, bufferType: RPSampleBufferType) {
        writeQueue.sync {
            if assetWriter == nil {
                if bufferType == .audioApp {
                    setupWriter(buffer: buffer)
                }
            }
            
            if assetWriter == nil {
                return
            }
            
            if self.assetWriter?.status == .unknown {
                print("Start writing")
                let startTime = CMSampleBufferGetPresentationTimeStamp(buffer)
                self.assetWriter?.startWriting()
                self.assetWriter?.startSession(atSourceTime: startTime)
            }
            if self.assetWriter?.status == .failed {
                print("assetWriter status: failed error: \(String(describing: self.assetWriter?.error))")
                return
            }
            
            if CMSampleBufferDataIsReady(buffer) == true {
                if bufferType == .video {
                    if let videoInput = self.videoInput, videoInput.isReadyForMoreMediaData {
                        videoInput.append(buffer)
                    }
                } else if bufferType == .audioApp {
                    if let audioInput = self.audioInput, audioInput.isReadyForMoreMediaData {
                        audioInput.append(buffer)
                    }
                }
            }
        }
    }
    
    public func finishWriting() {
        writeQueue.sync {
            self.assetWriter?.finishWriting(completionHandler: {
                print("finishWriting")
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: URL(fileURLWithPath: self.filePath))
                }) { saved, error in
                    if saved {
                        let alertController = UIAlertController(title: "Your video was successfully saved", message: nil, preferredStyle: .alert)
                        let defaultAction = UIAlertAction(title: "OK", style: .default, handler: nil)
                        alertController.addAction(defaultAction)
                        if let topVC = UIApplication.getTopViewController() {
                            topVC.present(alertController, animated: true, completion: nil)
                        }
                    }
                }
            })
        }
    }
}
