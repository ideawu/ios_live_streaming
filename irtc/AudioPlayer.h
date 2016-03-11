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

+ (AudioPlayer *)AACPlayerWithSampleRate:(int)sampleRate channels:(int)channels;
- (id)setSampleRate:(int)sampleRate channels:(int)channels;

- (void)stop;
- (void)appendData:(NSData *)data;

@end
