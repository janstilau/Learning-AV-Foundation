#import "THPlayerController.h"
#import <AVFoundation/AVFoundation.h>

@interface THPlayerController () <AVAudioPlayerDelegate>

@property (strong, nonatomic) NSArray *players;

@end

/*
 
 AVAudioPlayer
 
 Use an audio player to:
 Play audio of any duration from a file or buffer // 一定是本地数据. TTSPlayer.
 Control the volume, panning, rate, and looping behavior of the played audio
 Pan: Set this property value to position the audio in the stereo field. Use a value of -1.0 to indicate full left, 1.0 for full right, and 0.0 for center.
 Access playback-level metering data
 Play multiple sounds simultaneously by synchronizing the playback of multiple players
 
 */

@implementation THPlayerController

#pragma mark - Initialization

- (id)init {
    self = [super init];
    if (self) {
        AVAudioPlayer *guitarPlayer = [self playerForFile:@"guitar"];
        AVAudioPlayer *bassPlayer = [self playerForFile:@"bass"];
        AVAudioPlayer *drumsPlayer = [self playerForFile:@"drums"];
        
        guitarPlayer.delegate = self;
        
        _players = @[guitarPlayer, bassPlayer, drumsPlayer];
        
        NSNotificationCenter *nsnc = [NSNotificationCenter defaultCenter];
        [nsnc addObserver:self
                 selector:@selector(handleRouteChange:)
                     name:AVAudioSessionRouteChangeNotification
                   object:[AVAudioSession sharedInstance]];
    }
    return self;
}

- (AVAudioPlayer *)playerForFile:(NSString *)name {
    
    NSURL *fileURL = [[NSBundle mainBundle] URLForResource:name
                                             withExtension:@"caf"];
    
    NSError *error;
    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:fileURL
                                                                   error:&error];
    if (player) {
        player.numberOfLoops = 1; // loop indefinitely
        player.enableRate = YES;
        
        /*
            prepareToPlay
         

         Calling this method preloads audio buffers and acquires the audio hardware necessary for playback. This method activates the audio session, so pass false to setActive(_:) if immediate playback isn’t necessary. For example, when using the category option duckOthers, this method lowers the audio outside of the app.
         The system calls this method when using the method play(), but calling it in advance minimizes the delay between calling play() and the start of sound output.
         Calling stop(), or allowing a sound to finish playing, undoes this setup.
         
         In step 1 of Figure 1-4, the application primes the playback audio queue. The application invokes the callback once for each of the audio queue buffers, filling them and adding them to the buffer queue. Priming ensures that playback can start instantly when your application calls the AudioQueueStart function (step 2).
         */
        [player prepareToPlay];
        
        player.delegate = self;
    } else {
        NSLog(@"Error creating player: %@", [error localizedDescription]);
    }
    
    return player;
}


#pragma mark - Global playback control methods

- (void)play {
    if (!self.playing) {
        /*
         
            Plays audio asynchronously, starting at a specified point in the audio output device’s timeline.
         */
        NSTimeInterval delayTime = [self.players[0] deviceCurrentTime] + 0.01;
        for (AVAudioPlayer *player in self.players) {
            [player playAtTime:delayTime];
        }
        self.playing = YES;
    }
}

/*
    Pause
    Unlike calling stop(), pausing playback doesn’t deallocate hardware resources. It leaves the audio ready to resume playback from where it stops.
 
    Stop
    Calling this method undoes the resource allocation the system performs in prepareToPlay() or play(). It doesn’t reset the player’s currentTime value to 0, so playback resumes from where it stops.
 */

- (void)stop {
    if (self.playing) {
        for (AVAudioPlayer *player in self.players) {
            [player stop];
            player.currentTime = 0.0f;
        }
        self.playing = NO;
    }
}

- (void)adjustRate:(float)rate {
    for (AVAudioPlayer *player in self.players) {
        player.rate = rate;
    }
}


#pragma mark - Player-specific methods

- (void)adjustPan:(float)pan forPlayerAtIndex:(NSUInteger)index {
    if ([self isValidIndex:index]) {
        AVAudioPlayer *player = self.players[index];
        player.pan = pan;
    }
}

- (void)adjustVolume:(float)volume forPlayerAtIndex:(NSUInteger)index {
    if ([self isValidIndex:index]) {
        AVAudioPlayer *player = self.players[index];
        player.volume = volume;
    }
}

- (BOOL)isValidIndex:(NSUInteger)index {
    return index == 0 || index < self.players.count;
}


#pragma mark - Interruption Handlers

//
// The following two methods have been deprecated.
// Replace with AVAudioSession notification handlers in your production code.
//

- (void)audioPlayerBeginInterruption:(AVAudioPlayer *)player {
    [self stop];
    if (self.delegate) {
        [self.delegate playbackStopped];
    }
}

- (void)audioPlayerEndInterruption:(AVAudioPlayer *)player
                       withOptions:(NSUInteger)options {
    
    if (options == AVAudioSessionInterruptionOptionShouldResume) {
        [self play];
        if (self.delegate) {
            [self.delegate playbackBegan];
        }
    }
}

/*
    在播放的过程中, 打断点, 会发现以下, 和 CoreAudio 相关的线程.
    com.apple.coreaudio.AQClient (11)
    com.apple.audio.IOThread.client (13)
    AQConverterThread (26)
 */
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    NSLog(@"%s", __func__);
}

#pragma mark - Route Change Handler

- (void)handleRouteChange:(NSNotification *)notification {
    
    NSDictionary *info = notification.userInfo;
    
    AVAudioSessionRouteChangeReason reason =
    [info[AVAudioSessionRouteChangeReasonKey] unsignedIntValue];
    
    if (reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable) {
        
        AVAudioSessionRouteDescription *previousRoute =
        info[AVAudioSessionRouteChangePreviousRouteKey];
        
        AVAudioSessionPortDescription *previousOutput = previousRoute.outputs[0];
        NSString *portType = previousOutput.portType;
        
        if ([portType isEqualToString:AVAudioSessionPortHeadphones]) {
            [self stop];
            [self.delegate playbackStopped];
        }
    }
}

@end
