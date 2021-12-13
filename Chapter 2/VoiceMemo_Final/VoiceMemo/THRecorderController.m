#import "THRecorderController.h"
#import <AVFoundation/AVFoundation.h>
#import "THMemo.h"
#import "THLevelPair.h"
#import "THMeterTable.h"

/*
 
 AVAudioRecorder 本地的数据的控制.
 
 An object that records audio data to a file.
 
 Use an audio recorder to:
 Record audio from the system’s active input device
 Record for a specified duration or until the user stops recording
 Pause and resume a recording
 Access recording-level metering data
 */

/*
    Controller.
    Player.
    Session.
    Uploader.
 */
@interface THRecorderController () <AVAudioRecorderDelegate>

@property (strong, nonatomic) AVAudioPlayer *player;
@property (strong, nonatomic) AVAudioRecorder *recorder;
@property (strong, nonatomic) THRecordingStopCompletionHandler completionHandler;
@property (strong, nonatomic) THMeterTable *meterTable;

@end

@implementation THRecorderController

- (id)init {
    self = [super init];
    if (self) {
        NSString *tmpDir = NSTemporaryDirectory();
        NSString *filePath = [tmpDir stringByAppendingPathComponent:@"memo.caf"];
        NSURL *fileURL = [NSURL fileURLWithPath:filePath];
        
        
        /*
         AVFormatIDKeys:
         kAudioFormatLinearPCM
         kAudioFormatMPEG4AAC
         kAudioFormatAppleLossless
         kAudioFormatAppleIMA4
         kAudioFormatiLBC
         kAudioFormatULaw
         
         
         AVSampleRateKey:
         8 kHz to 192 kHz
         
         
         AVNumberOfChannelsKey:
         1 to 64
         */
        NSDictionary *settings = @{
            AVFormatIDKey : @(kAudioFormatAppleIMA4), // 音频文件的存储格式
            AVSampleRateKey : @44100.0f, // 采样率
            AVNumberOfChannelsKey : @1, // 声道数
            AVEncoderBitDepthHintKey : @16, // 位深.  --> 少一个采样格式.
            AVEncoderAudioQualityKey : @(AVAudioQualityMedium)
        };
        
        NSError *error;
        // 使用, 上面的属性, 以及存储文件位置, 来初始化一个 AVAudioRecorder 对象.
        // AVAudioRecorder 可以将录制过程中的音频数据, 按照 Setting 里面的配置, 放置到 File 的文件末尾.
        self.recorder = [[AVAudioRecorder alloc] initWithURL:fileURL settings:settings error:&error];
        if (self.recorder) {
            self.recorder.delegate = self;
            self.recorder.meteringEnabled = YES;
            [self.recorder prepareToRecord];
        } else {
            NSLog(@"Error: %@", [error localizedDescription]);
        }
        
        _meterTable = [[THMeterTable alloc] init];
    }
    
    return self;
}

- (BOOL)record {
    return [self.recorder record];
}

- (void)pause {
    [self.recorder pause];
}

/*
 Block 存储, 然后调用 Stop. 在代理方法里面, 触发 completionHandler
 */
- (void)stopWithCompletionHandler:(THRecordingStopCompletionHandler)handler {
    self.completionHandler = handler;
    [self.recorder stop];
}

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)success {
    if (self.completionHandler) {
        self.completionHandler(success);
    }
}

- (void)saveRecordingWithName:(NSString *)name completionHandler:(THRecordingSaveCompletionHandler)handler {
    
    NSTimeInterval timestamp = [NSDate timeIntervalSinceReferenceDate];
    NSString *filename = [NSString stringWithFormat:@"%@-%f.m4a", name, timestamp];
    
    NSString *docsDir = [self documentsDirectory];
    NSString *destPath = [docsDir stringByAppendingPathComponent:filename];
    
    NSURL *srcURL = self.recorder.url;
    NSURL *destURL = [NSURL fileURLWithPath:destPath];
    
    NSError *error;
    BOOL success = [[NSFileManager defaultManager] copyItemAtURL:srcURL toURL:destURL error:&error];
    // 将, 文件转移都相应的位置, 然后把文件的相关信息, 包装成为一个 Model 对象.
    if (success) {
        handler(YES, [THMemo memoWithTitle:name url:destURL]);
        [self.recorder prepareToRecord];
    } else {
        handler(NO, error);
    }
}

- (NSString *)documentsDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths objectAtIndex:0];
}

- (THLevelPair *)levels {
    [self.recorder updateMeters];
    float avgPower = [self.recorder averagePowerForChannel:0];
    float peakPower = [self.recorder peakPowerForChannel:0];
    float linearLevel = [self.meterTable valueForPower:avgPower];
    float linearPeak = [self.meterTable valueForPower:peakPower];
    return [THLevelPair levelsWithLevel:linearLevel peakLevel:linearPeak];
}

- (NSString *)formattedCurrentTime {
    NSUInteger time = (NSUInteger)self.recorder.currentTime;
    NSInteger hours = (time / 3600);
    NSInteger minutes = (time / 60) % 60;
    NSInteger seconds = time % 60;
    
    NSString *format = @"%02i:%02i:%02i";
    return [NSString stringWithFormat:format, hours, minutes, seconds];
}

- (BOOL)playbackMemo:(THMemo *)memo {
    [self.player stop];
    self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:memo.url error:nil];
    if (self.player) {
        [self.player play];
        return YES;
    }
    return NO;
}

// This method is now deprecated. You should use AVAudioSession notification handlers instead.
- (void)audioRecorderBeginInterruption:(AVAudioRecorder *)recorder {
    if (self.delegate) {
        [self.delegate interruptionBegan];
    }
}

@end
