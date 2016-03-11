//
//  AACCodec.h
//  irtc
//
//  Created by ideawu on 3/11/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@interface AACCodec : NSObject

- (void)setupCodecWithFormat:(AudioStreamBasicDescription)srcFormat dstFormat:(AudioStreamBasicDescription)dstFormat;
- (void)setupCodecFromSampleBuffer:(CMSampleBufferRef)sampleBuffer;

- (void)start:(void (^)(NSData *data, double duration))callback;
- (void)shutdown;

- (void)encodePCM:(NSData *)raw;
- (void)decodeAAC:(NSData *)aac;

@end
