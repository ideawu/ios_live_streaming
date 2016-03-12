//
//  AudioEncoder.h
//  irtc
//
//  Created by ideawu on 3/9/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@interface AudioEncoder : NSObject

- (void)start:(void (^)(NSData *aac, double pts, double duration))callback;
- (void)shutdown;

//- (void)encode:(NSData *)raw;
- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer;

@end
