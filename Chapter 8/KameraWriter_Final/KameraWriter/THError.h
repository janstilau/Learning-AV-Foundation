FOUNDATION_EXPORT NSString * const THCameraErrorDomain;

typedef NS_ENUM(NSInteger, THCameraErrorCode) {
    THCameraErrorFailedToAddInput = 1000,
    THCameraErrorFailedToAddOutput,
    THCameraErrorHighFrameRateCaptureNotSupported
};
