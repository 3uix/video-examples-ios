//
//  CameraEngine.swift
//  naruhodo
//
//  Created by FUJIKI TAKESHI on 2014/11/10.
//  Copyright (c) 2014年 Takeshi Fujiki. All rights reserved.
//

import Foundation
import AVFoundation
import AssetsLibrary

class SlowCameraEngine : NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate{

    class SlowVideoWriter : NSObject {
        var fileWriter: AVAssetWriter!
        var videoInput: AVAssetWriterInput!
        var audioInput: AVAssetWriterInput!
        
        init(fileUrl:URL!, height:Int, width:Int, channels:Int, samples:Float64){
            fileWriter = try? AVAssetWriter(outputURL: fileUrl, fileType: AVFileTypeQuickTimeMovie)
            
            let videoOutputSettings: Dictionary<String, AnyObject> = [
                AVVideoCodecKey : AVVideoCodecH264 as AnyObject,
                AVVideoWidthKey : width as AnyObject,
                AVVideoHeightKey : height as AnyObject
            ]
            videoInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: videoOutputSettings)
            videoInput.expectsMediaDataInRealTime = true
            videoInput.transform = CGAffineTransform(rotationAngle: CGFloat(M_PI)/2)
            fileWriter.add(videoInput)
            
            let audioOutputSettings: Dictionary<String, AnyObject> = [
                AVFormatIDKey : Int(kAudioFormatMPEG4AAC) as AnyObject,
                AVNumberOfChannelsKey : channels as AnyObject,
                AVSampleRateKey : samples as AnyObject,
                AVEncoderBitRateKey : 128000 as AnyObject
            ]
            audioInput = AVAssetWriterInput(mediaType: AVMediaTypeAudio, outputSettings: audioOutputSettings)
            audioInput.expectsMediaDataInRealTime = true
            fileWriter.add(audioInput)
        }
        
        func write(_ sample: CMSampleBuffer, isVideo: Bool){
            if CMSampleBufferDataIsReady(sample) {
                if fileWriter.status == AVAssetWriterStatus.unknown {
                    Logger.log("Start writing, isVideo = \(isVideo), status = \(fileWriter.status.rawValue)")
                    let startTime = CMSampleBufferGetPresentationTimeStamp(sample)
                    fileWriter.startWriting()
                    fileWriter.startSession(atSourceTime: startTime)
                }
                if fileWriter.status == AVAssetWriterStatus.failed {
                    Logger.log("Error occured, isVideo = \(isVideo), status = \(fileWriter.status.rawValue), \(fileWriter.error!.localizedDescription)")
                    return
                }
                if isVideo {
                    if videoInput.isReadyForMoreMediaData {
                        videoInput.append(sample)
                    }
                }else{
                    if audioInput.isReadyForMoreMediaData {
                        audioInput.append(sample)
                    }
                }
            }
        }
        
        func finish(_ callback: @escaping (Void) -> Void){
            fileWriter.finishWriting(completionHandler: callback)
        }
    }
    
    let captureSession = AVCaptureSession()
    var isCapturing = false
    let slowRatio = 2
    
    fileprivate let videoDevice = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
    fileprivate let audioDevice = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeAudio)
    fileprivate var videoWriter : SlowVideoWriter?
    
    fileprivate var height = 0
    fileprivate var width = 0
    
    fileprivate let recordingQueue = DispatchQueue(label: "com.takecian.RecordingQueue", attributes: [])

    fileprivate var currentFrameCount: Int64 = 0
    
    fileprivate var filePath: String {
        get {
            let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
            let documentsDirectory = paths[0] as String
            let filePath : String = "\(documentsDirectory)/video.mov"
            return filePath
        }
    }
    
    fileprivate var filePathUrl: URL {
        get {
            return URL(fileURLWithPath: filePath)
        }
    }
    
    func startup(){
        var selectedFormat: AVCaptureDeviceFormat?
        var maxWidth: Int32 = 0
        
        for format in (videoDevice?.formats)! {
            for range in (format as AnyObject).videoSupportedFrameRateRanges {
                if #available(iOS 9.0, *) {
                    let desc = (format as AnyObject).formatDescription!
                    let dimensions = CMVideoFormatDescriptionGetDimensions(desc)
                    let width = dimensions.width
                    if 60 <= (range as AnyObject).maxFrameRate  && width >= maxWidth {
                        selectedFormat = format as? AVCaptureDeviceFormat
                        maxWidth = width
                    }
                }
            }
        }
        
        if let format = selectedFormat {
            do {
                try videoDevice?.lockForConfiguration()
                videoDevice?.activeFormat = format
                videoDevice?.activeVideoMinFrameDuration = CMTimeMake(1, 60)
                videoDevice?.unlockForConfiguration()
            } catch {
                
            }
        }
        
        let videoInput = try! AVCaptureDeviceInput(device: videoDevice) as AVCaptureDeviceInput
        captureSession.addInput(videoInput)

        let audioInput = try! AVCaptureDeviceInput(device: audioDevice) as AVCaptureDeviceInput
        captureSession.addInput(audioInput)
        
        // video output
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.setSampleBufferDelegate(self, queue: recordingQueue)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as AnyHashable : Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        ]
        captureSession.addOutput(videoDataOutput)
        captureSession.sessionPreset = AVCaptureSessionPresetiFrame1280x720
        
        height = videoDataOutput.videoSettings["Height"] as! Int!
        width = videoDataOutput.videoSettings["Width"] as! Int!
        
        // audio output
        let audioDataOutput = AVCaptureAudioDataOutput()
        audioDataOutput.setSampleBufferDelegate(self, queue: recordingQueue)
        captureSession.addOutput(audioDataOutput)
     
        captureSession.startRunning()
    }
    
    func shutdown(){
        captureSession.stopRunning()
    }

    func start(){
        if !isCapturing{
            Logger.log("in")
            isCapturing = true
        }
    }
    
    func stop(){
        if isCapturing{
            isCapturing = false
            DispatchQueue.main.async(execute: { () -> Void in
                Logger.log("in")
                self.videoWriter!.finish { () -> Void in
                    Logger.log("Recording finished.")
                    self.videoWriter = nil
                    let assetsLib = ALAssetsLibrary()
                    assetsLib.writeVideoAtPath(toSavedPhotosAlbum: self.filePathUrl, completionBlock: {
                        (nsurl, error) -> Void in
                        Logger.log("Transfer video to library finished.")
                    })
                }
            })
        }
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!){
        guard isCapturing else { return }
        
        let isVideo = captureOutput is AVCaptureVideoDataOutput
            
        if videoWriter == nil && !isVideo {
            let fileManager = FileManager()
            if fileManager.fileExists(atPath: filePath) {
                do {
                    try fileManager.removeItem(atPath: filePath)
                } catch _ {
                }
            }
            
            let fmt = CMSampleBufferGetFormatDescription(sampleBuffer)
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt!)
            
            Logger.log("setup writer")
            videoWriter = SlowVideoWriter(
                fileUrl: filePathUrl,
                height: height, width: width,
                channels: Int((asbd?.pointee.mChannelsPerFrame)!),
                samples: (asbd?.pointee.mSampleRate)!
            )
        }
        
        if !isVideo {
            return
        }
        
        currentFrameCount += 1
        
        var buffer = sampleBuffer
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        buffer = setTimeStamp(sampleBuffer, newTime: CMTimeAdd(timestamp, CMTimeMake(1 * currentFrameCount, 60)))

        Logger.log("write")
        videoWriter?.write(buffer!, isVideo: isVideo)
    }
    
    fileprivate func setTimeStamp(_ sample: CMSampleBuffer, newTime: CMTime) -> CMSampleBuffer {
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sample, 0, nil, &count);
        var info = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(duration: CMTimeMake(0, 0), presentationTimeStamp: CMTimeMake(0, 0), decodeTimeStamp: CMTimeMake(0, 0)), count: count)
        CMSampleBufferGetSampleTimingInfoArray(sample, count, &info, &count);
        
        for i in 0..<count {
            info[i].decodeTimeStamp = newTime
            info[i].presentationTimeStamp = newTime
        }
        
        var out: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(nil, sample, count, &info, &out);
        return out!
    }
}
