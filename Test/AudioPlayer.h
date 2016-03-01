//
//  AudioPlayer.h
//  VideoTest
//
//  Created by ideawu on 2/29/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface AudioPlayer : NSObject

- (void)start;
- (void)stop;
- (void)appendSampleBuffer:(CMSampleBufferRef)sampleBuffer;

@end
