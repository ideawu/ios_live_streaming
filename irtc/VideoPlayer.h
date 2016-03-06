//
//  VideoPlayer.h
//  irtc
//
//  Created by ideawu on 16-3-6.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import "VideoClip.h"

/*
 http://stackoverflow.com/questions/29525000/how-to-use-videotoolbox-to-decompress-h-264-video-stream/


 Video Deocde Acceleration Framework for Mac
 https://developer.apple.com/library/mac/technotes/tn2267/_index.html
 */

@interface VideoPlayer : NSObject

@property (nonatomic, retain) AVSampleBufferDisplayLayer *videoLayer;

- (void)play;
//- (void)pause;
//- (void)stop;

- (void)addClip:(VideoClip *)clip;

@end
