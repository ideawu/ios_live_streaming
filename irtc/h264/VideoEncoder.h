//
//  AVEncoder.h
//  Encoder Demo
//
//  Created by Geraint Davies on 14/01/2013.
//  Copyright (c) 2013 GDCL http://www.gdcl.co.uk/license.htm
//

#import <AVFoundation/AVFoundation.h>

// TODO: 处理帧乱序!
typedef void (^encoder_handler_t)(NSData *nalu, double pts);

@interface VideoEncoder : NSObject

+ (VideoEncoder*)encoderForHeight:(int)height andWidth:(int)width bitrate:(int)bitrate;

- (void) encodeWithBlock:(encoder_handler_t) block onParams:(void (^)(NSData *sps, NSData *pps))paramsHandler;
- (void) encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (void) shutdown;

@end
