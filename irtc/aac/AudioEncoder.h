//
//  AudioEncoder.h
//  irtc
//
//  Created by ideawu on 3/9/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@interface AudioEncoder : NSObject

- (void)encodeWithBlock:(void (^)(NSData *data, double pts, double duration))callback;
- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (void)shutdown;

@end
