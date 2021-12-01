#import <AVFoundation/AVFoundation.h>

@protocol THMovieWriterDelegate <NSObject>

- (void)didWriteMovieAtURL:(NSURL *)outputURL;

@end

@interface THMovieWriter : NSObject

- (id)initWithVideoSettings:(NSDictionary *)videoSettings                   // 1
              audioSettings:(NSDictionary *)audioSettings
              dispatchQueue:(dispatch_queue_t)dispatchQueue;

- (void)startWriting;
- (void)stopWriting;

@property (nonatomic) BOOL isWriting;

@property (weak, nonatomic) id<THMovieWriterDelegate> delegate;             // 2

- (void)processSampleBuffer:(CMSampleBufferRef)sampleBuffer;                // 3

@end
