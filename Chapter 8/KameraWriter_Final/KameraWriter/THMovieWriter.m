#import "THMovieWriter.h"
#import <AVFoundation/AVFoundation.h>
#import "THContextManager.h"
#import "THFunctions.h"
#import "THPhotoFilters.h"
#import "THNotifications.h"

static NSString *const THVideoFilename = @"movie.mov";

@interface THMovieWriter ()

/*
    AVAssetWriter 就可以认为是 FileOutput 的实现逻辑. 
 */

/*
    An object that writes media data to a container file.
 
    You use an asset writer to write media to file formats such as the QuickTime movie file format and MPEG-4 file format.
    An asset writer automatically supports interleaving media data from concurrent tracks for efficient playback and storage.
    It can reencode media samples it writes to the output file, and may also write collections of metadata to the output file.
 */
@property (strong, nonatomic) AVAssetWriter *assetWriter;                   // 1

/*
 An object that appends media samples to a track in an asset writer’s output file.
 */
@property (strong, nonatomic) AVAssetWriterInput *assetWriterVideoInput;
@property (strong, nonatomic) AVAssetWriterInput *assetWriterAudioInput;

/*
 A pixel buffer adaptor provides a pixel buffer pool that you use to allocate pixel buffers to the output file. Using the provided pool for buffer allocation is typically more efficient than managing your own pool.
 这个东西, 就是为了减少内存分配而创建的, 里面一定会有内存的复用机制.
 */
@property (strong, nonatomic) AVAssetWriterInputPixelBufferAdaptor *assetWriterInputPixelBufferAdaptor;

@property (strong, nonatomic) dispatch_queue_t dispatchQueue;

@property (weak, nonatomic) CIContext *ciContext;
@property (nonatomic) CGColorSpaceRef colorSpace;
@property (strong, nonatomic) CIFilter *activeFilter;

@property (strong, nonatomic) NSDictionary *videoSettings;
@property (strong, nonatomic) NSDictionary *audioSettings;

@property (nonatomic) BOOL firstSample;

@end

@implementation THMovieWriter

- (id)initWithVideoSettings:(NSDictionary *)videoSettings
              audioSettings:(NSDictionary *)audioSettings
              dispatchQueue:(dispatch_queue_t)dispatchQueue {
    
    self = [super init];
    if (self) {
        _videoSettings = videoSettings;
        _audioSettings = audioSettings;
        _dispatchQueue = dispatchQueue;
        
        _ciContext = [THContextManager sharedInstance].ciContext;           // 3
        _colorSpace = CGColorSpaceCreateDeviceRGB();
        
        _activeFilter = [THPhotoFilters defaultFilter];
        _firstSample = YES;
        
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];    // 4
        [nc addObserver:self
               selector:@selector(filterChanged:)
                   name:THFilterSelectionChangedNotification
                 object:nil];
    }
    return self;
}

- (void)dealloc {
    CGColorSpaceRelease(_colorSpace);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)filterChanged:(NSNotification *)notification {
    self.activeFilter = [notification.object copy];
}

/*
    在调用, startWriting 的时候, 才会去创建 AVAssetWriter 对象.
 */
- (void)startWriting {
    dispatch_async(self.dispatchQueue, ^{                                   // 1
        
        NSError *error = nil;
        
        NSString *fileType = AVFileTypeQuickTimeMovie;
        self.assetWriter = [AVAssetWriter assetWriterWithURL:[self outputURL] fileType:fileType error:&error];
        
        if (!self.assetWriter || error) {
            NSString *formatString = @"Could not create AVAssetWriter: %@";
            NSLog(@"%@", [NSString stringWithFormat:formatString, error]);
            return;
        }
        
        /*
            Writer 的目的, 是将音视频的原始信息, 添加到封装文件里面.
            所以, 这些原始信息如何进行输入, 是 Writer 内的逻辑 .
            从这个赋值来看, 在 AVAssetWriterInput 里面, 一定有着编码的动作.
         */
        self.assetWriterVideoInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo
                                                                    outputSettings:self.videoSettings];
        self.assetWriterVideoInput.expectsMediaDataInRealTime = YES;
        
        UIDeviceOrientation orientation = [UIDevice currentDevice].orientation;
        self.assetWriterVideoInput.transform =                              // 4
        THTransformForDeviceOrientation(orientation);
        
        NSDictionary *attributes = @{                                       // 5
            (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
            (id)kCVPixelBufferWidthKey : self.videoSettings[AVVideoWidthKey],
            (id)kCVPixelBufferHeightKey : self.videoSettings[AVVideoHeightKey],
            (id)kCVPixelFormatOpenGLESCompatibility : (id)kCFBooleanTrue
        };
        
        self.assetWriterInputPixelBufferAdaptor =                           // 6
        [[AVAssetWriterInputPixelBufferAdaptor alloc]
         initWithAssetWriterInput:self.assetWriterVideoInput
         sourcePixelBufferAttributes:attributes];
        
        
        if ([self.assetWriter canAddInput:self.assetWriterVideoInput]) {    // 7
            [self.assetWriter addInput:self.assetWriterVideoInput];
        } else {
            NSLog(@"Unable to add video input.");
            return;
        }
        
        self.assetWriterAudioInput =                                        // 8
        [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio
                                       outputSettings:self.audioSettings];
        
        self.assetWriterAudioInput.expectsMediaDataInRealTime = YES;
        
        if ([self.assetWriter canAddInput:self.assetWriterAudioInput]) {    // 9
            [self.assetWriter addInput:self.assetWriterAudioInput];
        } else {
            NSLog(@"Unable to add audio input.");
        }
        
        self.isWriting = YES;                                              // 10
        self.firstSample = YES;
    });
}

// 这里是实际的, 数据处理的方法.
- (void)processSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    
    // 如果, 没有 startWriting, 其实就是没有点击录制视频的按钮.
    // 所以, 实际上, Session 一直在传递数据过来.
    // 只不过录制视频开启后, 才会有存储的实现逻辑. 
    if (!self.isWriting) {
        return;
    }
    
    // CMFormatDescription 的数据类型, 没有暴露出来, 只能通过 C 风格的代码, 来获取对应的值.
    CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
    
    // 获取了, 这一帧的类型.
    CMMediaType mediaType = CMFormatDescriptionGetMediaType(formatDesc);
    
    if (mediaType == kCMMediaType_Video) {
        // 获取了, 帧一帧视频的时间点.
        CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        
        if (self.firstSample) {                                             // 2
            if ([self.assetWriter startWriting]) {
                /*
                 You must call this method after you call startWriting, but before you append sample data to asset writer inputs.
                 Each writing session has a start time that, where allowed by the file format you’re writing, defines the mapping from the timeline of source samples to the timeline of the written file.
                 In the case of the QuickTime movie file format, the first session begins at movie time 0, so a sample you append with timestamp T plays at movie time (T-startTime).
                 The writer adds samples with timestamps earlier than the start time to the output file, but they don’t display during playback.
                 If the earliest sample for an input has a timestamp later than the start time, the system inserts an empty edit to preserve synchronization between tracks of the output asset.
                 To end a session, call endSessionAtSourceTime:or finishWritingWithCompletionHandler:
                 */
                [self.assetWriter startSessionAtSourceTime:timestamp];
            } else {
                NSLog(@"Failed to start writing.");
            }
            self.firstSample = NO;
        }
        
        CVPixelBufferRef outputRenderBuffer = NULL;
        CVPixelBufferPoolRef pixelBufferPool = self.assetWriterInputPixelBufferAdaptor.pixelBufferPool;
        
        OSStatus err = CVPixelBufferPoolCreatePixelBuffer(NULL,             // 3
                                                          pixelBufferPool,
                                                          &outputRenderBuffer);
        if (err) {
            NSLog(@"Unable to obtain a pixel buffer from the pool.");
            return;
        }
        // 到了这里, outputRenderBuffer 就是当前的视频样本的缓存空间了. 可以向里面填充内容.
        
        CVPixelBufferRef imageBuffer =                                      // 4
        CMSampleBufferGetImageBuffer(sampleBuffer);
        
        // CIImage 的操作, 可以略过.
        CIImage *sourceImage = [CIImage imageWithCVPixelBuffer:imageBuffer
                                                       options:nil];
        
        [self.activeFilter setValue:sourceImage forKey:kCIInputImageKey];
        
        CIImage *filteredImage = self.activeFilter.outputImage;
        
        if (!filteredImage) {
            filteredImage = sourceImage;
        }
        
        // 将 filteredImage 的数据, 填充到了 outputRenderBuffer 内部.
        [self.ciContext render:filteredImage                                // 5
               toCVPixelBuffer:outputRenderBuffer
                        bounds:filteredImage.extent
                    colorSpace:self.colorSpace];
        
        // 将 outputRenderBuffer 的数据, 填充到了文件里面.
        if (self.assetWriterVideoInput.readyForMoreMediaData) {             // 6
            if (![self.assetWriterInputPixelBufferAdaptor
                  appendPixelBuffer:outputRenderBuffer
                  withPresentationTime:timestamp]) {
                NSLog(@"Error appending pixel buffer.");
            }
        }
        
        CVPixelBufferRelease(outputRenderBuffer);
        
    } else if (!self.firstSample && mediaType == kCMMediaType_Audio) {        // 7
        if (self.assetWriterAudioInput.isReadyForMoreMediaData) {
            // 对于音频来说, 就是直接的填充样本就可以了
            if (![self.assetWriterAudioInput appendSampleBuffer:sampleBuffer]) {
                NSLog(@"Error appending audio sample buffer.");
            }
        }
    }
    
}

- (void)stopWriting {
    
    self.isWriting = NO;                                                    // 1
    
    dispatch_async(self.dispatchQueue, ^{
        
        [self.assetWriter finishWritingWithCompletionHandler:^{             // 2
            
            if (self.assetWriter.status == AVAssetWriterStatusCompleted) {
                dispatch_async(dispatch_get_main_queue(), ^{                // 3
                    NSURL *fileURL = [self.assetWriter outputURL];
                    [self.delegate didWriteMovieAtURL:fileURL];
                });
            } else {
                NSLog(@"Failed to write movie: %@", self.assetWriter.error);
            }
        }];
    });
}

/*
    在, 生成临时的影片路径的时候, 有副作用, 把原来的文件进行了删除.
    会不会显示的在 StartWriting 里面调用删除的逻辑会好一点.
 */
- (NSURL *)outputURL {
    NSString *filePath =
    [NSTemporaryDirectory() stringByAppendingPathComponent:THVideoFilename];
    NSURL *url = [NSURL fileURLWithPath:filePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
    }
    return url;
}

@end
