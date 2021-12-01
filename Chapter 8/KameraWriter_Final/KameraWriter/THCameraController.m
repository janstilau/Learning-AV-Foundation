//
//  MIT License
//
//  Copyright (c) 2014 Bob McCune http://bobmccune.com/
//  Copyright (c) 2014 TapHarmonic, LLC http://tapharmonic.com/
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "THCameraController.h"
#import <AVFoundation/AVFoundation.h>
#import "THMovieWriter.h"
#import <AssetsLibrary/AssetsLibrary.h>

@interface THCameraController () <
AVCaptureVideoDataOutputSampleBufferDelegate,
AVCaptureAudioDataOutputSampleBufferDelegate,
THMovieWriterDelegate>

/*
    这个类, 就是专门用来, 处理录制过程中, 影片的原始数据的.
    A capture output that records video and provides access to video frames for processing.
 
    You use this output to process compressed or uncompressed frames from the captured video.
    You can access the frames with the captureOutput(_:didOutput:from:) delegate method.
 
    AVCaptureVideoDataOutput supports compressed video data output for macOS only.
 */
@property (strong, nonatomic) AVCaptureVideoDataOutput *videoDataOutput;
@property (strong, nonatomic) AVCaptureAudioDataOutput *audioDataOutput;

@property (strong, nonatomic) THMovieWriter *movieWriter;

@end

@implementation THCameraController

- (BOOL)setupSessionOutputs:(NSError **)error {
    
    self.videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];         // 1
    
    NSDictionary *outputSettings =
    @{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)};
    
    self.videoDataOutput.videoSettings = outputSettings;
    /*
     If this property is true, the output immediately discard frames that captured while the dispatch queue handling existing frames blocks in the captureOutput(_:didOutput:from:) delegate method.
     When set to false, the output gives delegates more time to process old frames before it discards new frames, but application memory usage may increase significantly as a result.
     The default is true.
     */
    self.videoDataOutput.alwaysDiscardsLateVideoFrames = NO;                // 2
    
    [self.videoDataOutput setSampleBufferDelegate:self
                                            queue:self.dispatchQueue];
    
    if ([self.captureSession canAddOutput:self.videoDataOutput]) {
        [self.captureSession addOutput:self.videoDataOutput];
    } else {
        return NO;
    }
    
    self.audioDataOutput = [[AVCaptureAudioDataOutput alloc] init];         // 3
    
    [self.audioDataOutput setSampleBufferDelegate:self
                                            queue:self.dispatchQueue];
    
    if ([self.captureSession canAddOutput:self.audioDataOutput]) {
        [self.captureSession addOutput:self.audioDataOutput];
    } else {
        return NO;
    }
    
    NSString *fileType = AVFileTypeQuickTimeMovie;
    
    /*
        Returns a video settings dictionary appropriate for capturing video to be recorded to a file with the specified codec and type.
     
     {
         AVVideoCodecKey = hvc1; // H.265 一种.
         AVVideoCompressionPropertiesKey =     {
             AllowFrameReordering = 1;
             AllowOpenGOP = 1;
             AverageBitRate = 4847616;
             ExpectedFrameRate = 30;
             MaxKeyFrameIntervalDuration = 1;
             MaxQuantizationParameter = 41;
             Priority = 80;
             ProfileLevel = "HEVC_Main_AutoLevel";
             RealTime = 1;
             RelaxAverageBitRateTarget = 1;
             SoftMinQuantizationParameter = 18;
         };
         AVVideoHeightKey = 720; // 视频的高度.
         AVVideoWidthKey = 1280; // 视频的宽度.
     }
        
     */
    NSDictionary *videoSettings =
    [self.videoDataOutput recommendedVideoSettingsForAssetWriterWithOutputFileType:fileType];
    
    NSDictionary *audioSettings =
    [self.audioDataOutput recommendedAudioSettingsForAssetWriterWithOutputFileType:fileType];
    
    self.movieWriter =
    [[THMovieWriter alloc] initWithVideoSettings:videoSettings
                                   audioSettings:audioSettings
                                   dispatchQueue:self.dispatchQueue];
    self.movieWriter.delegate = self;
    
    return YES;
}

- (NSString *)sessionPreset {
    return AVCaptureSessionPreset1280x720;
}

- (void)startRecording {
    [self.movieWriter startWriting];
    self.recording = YES;
}

- (void)stopRecording {
    [self.movieWriter stopWriting];
    self.recording = NO;
}


#pragma mark - Delegate methods

/*
    CaptureSession 会将, 音视频的原始数据, 通过这个方法, 暴露出来.
    这已经是子线程了.
 */
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    
    [self.movieWriter processSampleBuffer:sampleBuffer];
    
    if (captureOutput == self.videoDataOutput) {
        
        CVPixelBufferRef imageBuffer =
        CMSampleBufferGetImageBuffer(sampleBuffer);
        
        CIImage *sourceImage = [CIImage imageWithCVPixelBuffer:imageBuffer options:nil];
        
        /*
         <THPreviewView: 0x104a06570; frame = (0 0; 414 896); transform = [6.123233995736766e-17, 1, -1, 6.123233995736766e-17, 0, 0]; layer = <CAEAGLLayer: 0x2803fd260>>
         */
        [self.imageTarget setImage:sourceImage];
    }
}

- (void)didWriteMovieAtURL:(NSURL *)outputURL {
    
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    if ([library videoAtPathIsCompatibleWithSavedPhotosAlbum:outputURL]) {
        ALAssetsLibraryWriteVideoCompletionBlock completionBlock;
        completionBlock = ^(NSURL *assetURL, NSError *error){
            if (error) {
                [self.delegate assetLibraryWriteFailedWithError:error];
            }
        };
        [library writeVideoAtPathToSavedPhotosAlbum:outputURL
                                    completionBlock:completionBlock];
    }
}

@end
