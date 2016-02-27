
#import <Foundation/Foundation.h>

@interface LivePlayer : NSObject

+ (LivePlayer *)playerWithCALayer:(CALayer *)layer;

- (void)removeAllItems;

- (void)addMovieData:(NSData *)data;
- (void)addMovieData:(NSData *)data originalPath:(NSString *)originalPath;
- (void)addMovieFile:(NSString *)localFilePath;

- (void)play;

@end
