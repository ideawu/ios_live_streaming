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

- (void)setSps:(NSData *)sps pps:(NSData *)pps;

// 调用者负责释放内存
- (CMSampleBufferRef)processFrame:(NSData *)frame;

@end
