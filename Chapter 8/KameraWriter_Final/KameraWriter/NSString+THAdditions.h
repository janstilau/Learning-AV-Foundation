@interface NSString (THAdditions)

- (NSString *)stringByMatchingRegex:(NSString *)regex capture:(NSUInteger)capture;
- (BOOL)containsString:(NSString *)substring;

@end
