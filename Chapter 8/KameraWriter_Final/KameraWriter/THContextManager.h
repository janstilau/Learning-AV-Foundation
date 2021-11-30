@interface THContextManager : NSObject

+ (instancetype)sharedInstance;

@property (strong, nonatomic, readonly) EAGLContext *eaglContext;
@property (strong, nonatomic, readonly) CIContext *ciContext;

@end
