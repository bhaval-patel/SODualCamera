//
//  ViewController.swift
//  SODualCamera
//
//  Created by SOTSYS207 on 05/08/19.
//  Copyright © 2019 SOTSYS207. All rights reserved.
//

import UIKit
import AVFoundation
import Photos
import ReplayKit


class ViewController: UIViewController,AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate,RPPreviewViewControllerDelegate{

    
    var dualVideoSession = AVCaptureMultiCamSession()
    var audioDeviceInput: AVCaptureDeviceInput?
      
    @IBOutlet weak var backPreview: ViewPreview!
    var backDeviceInput:AVCaptureDeviceInput?
    var backVideoDataOutput = AVCaptureVideoDataOutput()
    var backViewLayer:AVCaptureVideoPreviewLayer?
    var backAudioDataOutput = AVCaptureAudioDataOutput()
    
    @IBOutlet weak var frontPreview: ViewPreview!
    var frontDeviceInput:AVCaptureDeviceInput?
    var frontVideoDataOutput = AVCaptureVideoDataOutput()
    var frontViewLayer:AVCaptureVideoPreviewLayer?
    var frontAudioDataOutput = AVCaptureAudioDataOutput()

    let dualVideoSessionQueue = DispatchQueue(label: "dual video session queue")
     
    let dualVideoSessionOutputQueue = DispatchQueue(label: "dual video session data output queue")

    let screenRecorder = RPScreenRecorder.shared()

    var isRecording = false

    var assetWriter:AssetWriter?
   
    //MARK:- View Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        setUp()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        #if targetEnvironment(simulator)
          let alertController = UIAlertController(title: "SODualCamera", message: "Please run on physical device", preferredStyle: .alert)
          alertController.addAction(UIAlertAction(title: "OK",style: .cancel, handler: nil))
          self.present(alertController, animated: true, completion: nil)
          return
        #endif
    }
    
    
    //MARK:- User Permission for Dual Video Session
    //ask user permissin for recording video from device
    func dualVideoPermisson(){
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                // The user has previously granted access to the camera.
                 configureDualVideo()
                break
                
            case .notDetermined:
                
                AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                    if granted{
                        self.configureDualVideo()
                    }
                })
                
                break
                
            default:
                // The user has previously denied access.
            DispatchQueue.main.async {
                let changePrivacySetting = "Device doesn't have permission to use the camera, please change privacy settings"
                let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
                let alertController = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
                
                alertController.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
                
                alertController.addAction(UIAlertAction(title: "Settings", style: .`default`,handler: { _ in
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL,  options: [:], completionHandler: nil)
                    }
                }))
                
                self.present(alertController, animated: true, completion: nil)
            }
        }
    }
    
    //MARK:- Setup Dual Video Session
    func setUp(){
        
        #if targetEnvironment(simulator)
            return
        #endif

               
        // Set up the back and front video preview views.
        
        backPreview.videoPreviewLayer.setSessionWithNoConnection(dualVideoSession)
        frontPreview.videoPreviewLayer.setSessionWithNoConnection(dualVideoSession)
        
        // Store the back and front video preview layers so we can connect them to their inputs
        backViewLayer = backPreview.videoPreviewLayer
        frontViewLayer = frontPreview.videoPreviewLayer
        
        // Keep the screen awake
        UIApplication.shared.isIdleTimerDisabled = true
        
        dualVideoPermisson()
        
        addGestures()
        
        let outputFileName = NSUUID().uuidString + ".mp4"
        assetWriter = AssetWriter(fileName: outputFileName)

    }
        
      
    func configureDualVideo(){
          addNotifer()
          dualVideoSessionQueue.async {
              self.setUpSession()
          }
      }
        
    func setUpSession(){
        if !AVCaptureMultiCamSession.isMultiCamSupported{
            DispatchQueue.main.async {
               let alertController = UIAlertController(title: "Error", message: "Device is not supporting multicam feature", preferredStyle: .alert)
               alertController.addAction(UIAlertAction(title: "OK",style: .cancel, handler: nil))
               self.present(alertController, animated: true, completion: nil)
            }
            return
        }
                  
        guard setUpBackCamera() else{
          
          DispatchQueue.main.async {
           let alertController = UIAlertController(title: "Error", message: "issue while setuping back camera", preferredStyle: .alert)
           alertController.addAction(UIAlertAction(title: "OK",style: .cancel, handler: nil))
           self.present(alertController, animated: true, completion: nil)
          }
          return
            
        }
        
        guard setUpFrontCamera() else{
            DispatchQueue.main.async {
                let alertController = UIAlertController(title: "Error", message: "issue while setuping front camera", preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: "OK",style: .cancel, handler: nil))
                self.present(alertController, animated: true, completion: nil)
            }
            return
        }
        
        guard setUpAudio() else{
             DispatchQueue.main.async {
                let alertController = UIAlertController(title: "Error", message: "issue while setuping audio session", preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: "OK",style: .cancel, handler: nil))
                self.present(alertController, animated: true, completion: nil)
              }
          return
        }
        
      dualVideoSessionQueue.async {
          self.dualVideoSession.startRunning()
      }
      
    }

        
    func setUpBackCamera() -> Bool{
        //start configuring dual video session
        dualVideoSession.beginConfiguration()
            defer {
                //save configuration setting
                dualVideoSession.commitConfiguration()
            }
                
            //search back camera
            guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                print("no back camera")
                return false
            }
            
            // append back camera input to dual video session
            do {
                backDeviceInput = try AVCaptureDeviceInput(device: backCamera)
                
                guard let backInput = backDeviceInput,dualVideoSession.canAddInput(backInput) else {
                    print("no back camera device input")
                    return false
                }
                dualVideoSession.addInputWithNoConnections(backInput)
            } catch {
                print("no back camera device input: \(error)")
                return false
            }
            
            // seach back video port
            guard let backDeviceInput = backDeviceInput,
                let backVideoPort = backDeviceInput.ports(for: .video, sourceDeviceType: backCamera.deviceType, sourceDevicePosition: backCamera.position).first else {
                print("no back camera input's video port")
                return false
            }
            
            // append back video ouput
            guard dualVideoSession.canAddOutput(backVideoDataOutput) else {
                print("no back camera output")
                return false
            }
            dualVideoSession.addOutputWithNoConnections(backVideoDataOutput)
            backVideoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            backVideoDataOutput.setSampleBufferDelegate(self, queue: dualVideoSessionOutputQueue)
            
            // connect back ouput to dual video connection
            let backOutputConnection = AVCaptureConnection(inputPorts: [backVideoPort], output: backVideoDataOutput)
            guard dualVideoSession.canAddConnection(backOutputConnection) else {
                print("no connection to the back camera video data output")
                return false
            }
            dualVideoSession.addConnection(backOutputConnection)
            backOutputConnection.videoOrientation = .portrait

            // connect back input to back layer
            guard let backLayer = backViewLayer else {
                return false
            }
            let backConnection = AVCaptureConnection(inputPort: backVideoPort, videoPreviewLayer: backLayer)
            guard dualVideoSession.canAddConnection(backConnection) else {
                print("no a connection to the back camera video preview layer")
                return false
            }
            dualVideoSession.addConnection(backConnection)
        
        return true
    }
    
        
    func setUpFrontCamera() -> Bool{
            
              //start configuring dual video session
            dualVideoSession.beginConfiguration()
            defer {
              //save configuration setting
                dualVideoSession.commitConfiguration()
            }
            
            //search front camera for dual video session
            guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                print("no front camera")
                return false
            }
            
            // append front camera input to dual video session
            do {
                frontDeviceInput = try AVCaptureDeviceInput(device: frontCamera)
                
                guard let frontInput = frontDeviceInput, dualVideoSession.canAddInput(frontInput) else {
                    print("no front camera input")
                    return false
                }
                dualVideoSession.addInputWithNoConnections(frontInput)
            } catch {
                print("no front input: \(error)")
                return false
            }
            
            // search front video port for dual video session
            guard let frontDeviceInput = frontDeviceInput,
                let frontVideoPort = frontDeviceInput.ports(for: .video, sourceDeviceType: frontCamera.deviceType, sourceDevicePosition: frontCamera.position).first else {
                print("no front camera device input's video port")
                return false
            }
            
            // append front video output to dual video session
            guard dualVideoSession.canAddOutput(frontVideoDataOutput) else {
                print("no the front camera video output")
                return false
            }
            dualVideoSession.addOutputWithNoConnections(frontVideoDataOutput)
            frontVideoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            frontVideoDataOutput.setSampleBufferDelegate(self, queue: dualVideoSessionOutputQueue)
            
            // connect front output to dual video session
            let frontOutputConnection = AVCaptureConnection(inputPorts: [frontVideoPort], output: frontVideoDataOutput)
            guard dualVideoSession.canAddConnection(frontOutputConnection) else {
                print("no connection to the front video output")
                return false
            }
            dualVideoSession.addConnection(frontOutputConnection)
            frontOutputConnection.videoOrientation = .portrait
            frontOutputConnection.automaticallyAdjustsVideoMirroring = false
            frontOutputConnection.isVideoMirrored = true

            // connect front input to front layer
            guard let frontLayer = frontViewLayer else {
                return false
            }
            let frontLayerConnection = AVCaptureConnection(inputPort: frontVideoPort, videoPreviewLayer: frontLayer)
            guard dualVideoSession.canAddConnection(frontLayerConnection) else {
                print("no connection to front layer")
                return false
            }
            dualVideoSession.addConnection(frontLayerConnection)
            frontLayerConnection.automaticallyAdjustsVideoMirroring = false
            frontLayerConnection.isVideoMirrored = true
            
            return true
    }
        
        
    func setUpAudio() -> Bool{
         //start configuring dual video session
        dualVideoSession.beginConfiguration()
        defer {
            //save configuration setting

            dualVideoSession.commitConfiguration()
        }
        
        // serach audio device for dual video session
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            print("no the microphone")
            return false
        }
        
        // append auido to dual video session
        do {
            audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
            
            guard let audioInput = audioDeviceInput,
                dualVideoSession.canAddInput(audioInput) else {
                    print("no audio input")
                    return false
            }
            dualVideoSession.addInputWithNoConnections(audioInput)
        } catch {
            print("no audio input: \(error)")
            return false
        }
        
        //search audio port back
        guard let audioInputPort = audioDeviceInput,
            let backAudioPort = audioInputPort.ports(for: .audio, sourceDeviceType: audioDevice.deviceType, sourceDevicePosition: .back).first else {
            print("no front back port")
            return false
        }
        
        // search audio port front
        guard let frontAudioPort = audioInputPort.ports(for: .audio, sourceDeviceType: audioDevice.deviceType, sourceDevicePosition: .front).first else {
            print("no front audio port")
            return false
        }
        
        // append back output to dual video session
        guard dualVideoSession.canAddOutput(backAudioDataOutput) else {
            print("no back audio data output")
            return false
        }
        dualVideoSession.addOutputWithNoConnections(backAudioDataOutput)
        backAudioDataOutput.setSampleBufferDelegate(self, queue: dualVideoSessionOutputQueue)
        
        // append front ouput to dual video session
        guard dualVideoSession.canAddOutput(frontAudioDataOutput) else {
            print("no front audio data output")
            return false
        }
        dualVideoSession.addOutputWithNoConnections(frontAudioDataOutput)
        frontAudioDataOutput.setSampleBufferDelegate(self, queue: dualVideoSessionOutputQueue)
        
        // add back output to dual video session
        let backOutputConnection = AVCaptureConnection(inputPorts: [backAudioPort], output: backAudioDataOutput)
        guard dualVideoSession.canAddConnection(backOutputConnection) else {
            print("no back audio connection")
            return false
        }
        dualVideoSession.addConnection(backOutputConnection)
        
        // add front output to dual video session
        let frontutputConnection = AVCaptureConnection(inputPorts: [frontAudioPort], output: frontAudioDataOutput)
        guard dualVideoSession.canAddConnection(frontutputConnection) else {
            print("no front audio connection")
            return false
        }
        dualVideoSession.addConnection(frontutputConnection)
        
        return true
    }

    
     //MARK:- Add Gestures and Handle Gesture Response
    
    func addGestures(){
        
        //add gesture single tap
        let tapSingle = UITapGestureRecognizer(target: self, action: #selector(self.handleSingleTap(_:)))
        tapSingle.numberOfTapsRequired = 1
        self.view.addGestureRecognizer(tapSingle)
        
        //add gesture double tap

        let tapDouble = UITapGestureRecognizer(target: self, action: #selector(self.handleDoubleTap(_:)))
        tapDouble.numberOfTapsRequired = 2
        self.view.addGestureRecognizer(tapDouble)
        
        //ask single tap detect onserver to wait for double tap gesture
        tapSingle.require(toFail: tapDouble)

    }
    
    
    @objc func handleSingleTap(_ sender: UITapGestureRecognizer) {
        print("startScreenRecording")
        guard screenRecorder.isAvailable else {
            print("Recording is not available at this time.")
            return
        }
        
        if !isRecording {
           // startRecord()
            startCapture()
        }
    }
    
    @objc func handleDoubleTap(_ sender: UITapGestureRecognizer) {
        print("stopScreenRecording")
        if isRecording{
            // stopRecord()
            stopCapture()
        }
           
    }
    
     //MARK:- ReplayKit
    func startRecord(){
        screenRecorder.isMicrophoneEnabled = true
        screenRecorder.startRecording{ [unowned self] (error) in
            self.isRecording = true
        }
    }
    
   
    
    func stopRecord(){
        screenRecorder.stopRecording { [unowned self] (preview, error) in
            print("Stopped recording")
            
            guard preview != nil else {
                print("Preview controller is not available.")
                return
            }
            
            let alert = UIAlertController(title: "Recording Completed", message: "Would you like to edit or delete your recording?", preferredStyle: .alert)
                
            let deleteAction = UIAlertAction(title: "Delete", style: .destructive, handler: { (action: UIAlertAction) in
                self.screenRecorder.discardRecording(handler: { () -> Void in
                    print("Recording suffessfully deleted.")
                })
            })
                
            let editAction = UIAlertAction(title: "Edit", style: .default, handler: { (action: UIAlertAction) -> Void in
                preview?.previewControllerDelegate = self as RPPreviewViewControllerDelegate
                self.present(preview!, animated: true, completion: nil)
            })
                
            alert.addAction(editAction)
            alert.addAction(deleteAction)
            self.present(alert, animated: true, completion: nil)
                
            self.isRecording = false
                        
        }
    }
    
    func startCapture() {
       screenRecorder.startCapture(handler: { (buffer, bufferType, err) in
            self.isRecording = true
            self.assetWriter!.write(buffer: buffer, bufferType: bufferType)
        }, completionHandler: {
            if let error = $0 {
                print(error)
            }
        })
    }
        
    func stopCapture() {
        screenRecorder.stopCapture {
            self.isRecording = false
            if let err = $0 {
                print(err)
            }
            self.assetWriter?.finishWriting()
        }
    }
    
    func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
           dismiss(animated: true)
    }
   
    //MARK:- Add and Handle Observers
    func addNotifer() {
        
        // A session can run only when the app is full screen. It will be interrupted in a multi-app layout.
        // Add observers to handle these session interruptions and inform the user.
                
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError), name: .AVCaptureSessionRuntimeError,object: dualVideoSession)
        
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted), name: .AVCaptureSessionWasInterrupted, object: dualVideoSession)
        
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded), name: .AVCaptureSessionInterruptionEnded, object: dualVideoSession)
    }
    
    
    @objc func sessionWasInterrupted(notification: NSNotification) {
            print("Session was interrupted")
    }
        
    @objc func sessionInterruptionEnded(notification: NSNotification) {
        print("Session interrupt ended")
    }
        
    @objc func sessionRuntimeError(notification: NSNotification) {
        guard let errorValue = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError else {
            return
        }
        
        let error = AVError(_nsError: errorValue)
        print("Capture session runtime error: \(error)")
        
        /*
        Automatically try to restart the session running if media services were
        reset and the last start running succeeded. Otherwise, enable the user
        to try to resume the session running.
        */
        if error.code == .mediaServicesWereReset {
            //Manage according to condition
        } else {
           //Manage according to condition
        }
    }
    
     //MARK:- AVCaptureOutput Delegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection){
    
    }

}

