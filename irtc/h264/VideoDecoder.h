//
//  VideoDecoder.h
//  irtc
//
//  Created by ideawu on 3/7/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

/*
 http://stackoverflow.com/questions/29525000/how-to-use-videotoolbox-to-decompress-h-264-video-stream/
 
 
 Video Deocde Acceleration Framework for Mac
 https://developer.apple.com/library/mac/technotes/tn2267/_index.html
 */

@interface VideoDecoder : NSObject

- (BOOL)readyForFrame;

- (void)setCallback:(void (^)(CVImageBufferRef imageBuffer))callback;
- (void)setSps:(NSData *)sps pps:(NSData *)pps;

- (void)appendFrame:(NSData *)frame;

@end
