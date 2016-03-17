//
//  Mp4FileVideoEncoder.h
//  irtc
//
//  Created by ideawu on 3/16/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@interface MP4FileVideoEncoder : NSObject

@property (nonatomic) int width;
@property (nonatomic) int height;

@property (nonatomic, readonly) NSData *sps;
@property (nonatomic, readonly) NSData *pps;

- (void)start:(void (^)(NSData *frame, double pts, double duration))callback;
- (void)shutdown;

- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer;

@end
