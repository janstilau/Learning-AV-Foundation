#import "THAssetsLibrary.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <AVFoundation/AVFoundation.h>

static NSString *const THThumbnailCreatedNotification = @"THThumbnailCreated";

@interface THAssetsLibrary ()

@property (strong, nonatomic) ALAssetsLibrary *library;

@end

@implementation THAssetsLibrary

- (instancetype)init {
    self = [super init];
    if (self) {
        _library = [[ALAssetsLibrary alloc] init];
    }
    return self;
}

- (void)writeImage:(UIImage *)image completionHandler:(THAssetsLibraryWriteCompletionHandler)completionHandler {
    
    [self.library writeImageToSavedPhotosAlbum:image.CGImage
                                   orientation:(NSInteger)image.imageOrientation
                               completionBlock:^(NSURL *assetURL, NSError *error) {
        if (!error) {
            [self postThumbnailNotifification:image];
            completionHandler(YES, nil);
        } else {
            completionHandler(NO, error);
        }
    }];
    
}

- (void)writeVideoAtURL:(NSURL *)videoURL
      completionHandler:(THAssetsLibraryWriteCompletionHandler)completionHandler {
    
    if ([self.library videoAtPathIsCompatibleWithSavedPhotosAlbum:videoURL]) {
        
        ALAssetsLibraryWriteVideoCompletionBlock completionBlock;
        
        completionBlock = ^(NSURL *assetURL, NSError *error){
            if (error) {
                completionHandler(NO, error);
            } else {
                [self generateThumbnailForVideoAtURL:videoURL];
                completionHandler(YES, nil);
            }
        };
        
        [self.library writeVideoAtPathToSavedPhotosAlbum:videoURL
                                         completionBlock:completionBlock];
    }
}

- (void)generateThumbnailForVideoAtURL:(NSURL *)videoURL {
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        /*
         AVAsynchronousKeyValueLoading
         
         Creating an asset doesn’t make all of its data immediately available.
         Instead, an asset waits to load its data until you perform an operation on it (for example, directly invoking any relevant AVAsset methods, implementing playback with an AVPlayerItem object, exporting with AVAssetExportSession, reading with an AVAssetReader, and so on).
         Although you can request the value of a property at any time, and it returns its value synchronously, the operation may block the calling thread until the request completes.
         
         To avoid blocking:
         If the asset hasn’t loaded a value, use the loadValuesAsynchronously(forKeys:completionHandler:) method to ask it to asynchronously load one or more of its values and notify you when it loads.
         Determine whether the value for a specified key is available using the statusOfValue(forKey:error:) method.
         
         这种 API 设计出来, 就一定要按照它的设计出来. 既然有一个 Get 函数了, 如果不使用这个 Get 函数, 提前获取这个属性现在的状态, 那么就是使用者的问题了.
         */
        AVAsset *asset = [AVAsset assetWithURL:videoURL];
        
        AVAssetImageGenerator *imageGenerator =
        [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
        imageGenerator.maximumSize = CGSizeMake(100.0f, 0.0f);
        imageGenerator.appliesPreferredTrackTransform = YES;
        CGImageRef imageRef = [imageGenerator copyCGImageAtTime:kCMTimeZero
                                                     actualTime:NULL
                                                          error:nil];
        UIImage *image = [UIImage imageWithCGImage:imageRef];
        CGImageRelease(imageRef);
        
        [self postThumbnailNotifification:image];
    });
}

- (void)postThumbnailNotifification:(UIImage *)image {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc postNotificationName:THThumbnailCreatedNotification object:image];
    });
}

@end
