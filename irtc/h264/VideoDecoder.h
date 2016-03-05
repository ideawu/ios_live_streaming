//
//  VideoDecoder.h
//  irtc
//
//  Created by ideawu on 3/5/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>

/*
 http://stackoverflow.com/questions/29525000/how-to-use-videotoolbox-to-decompress-h-264-video-stream/
 
 
 Video Deocde Acceleration Framework for Mac
 https://developer.apple.com/library/mac/technotes/tn2267/_index.html
 */

@interface VideoDecoder : NSObject

@property (nonatomic, retain) AVSampleBufferDisplayLayer *videoLayer;

- (void)setSps:(NSData *)sps pps:(NSData *)pps;
- (void)processFrame:(NSData *)frame pts:(double)pts;

@end
