//
//  AVEncoder.h
//  Encoder Demo
//
//  Created by Geraint Davies on 14/01/2013.
//  Copyright (c) 2013 GDCL http://www.gdcl.co.uk/license.htm
//

#import <AVFoundation/AVFoundation.h>

typedef int (^encoder_handler_t)(NSArray* frames, double pts);

@interface VideoEncoder : NSObject

+ (VideoEncoder*)encoderForHeight:(int)height andWidth:(int)width bitrate:(int)bitrate;

- (void) encodeWithBlock:(encoder_handler_t) block onParams:(void (^)(NSData *sps, NSData *pps))paramsHandler;
- (void) encodeFrame:(CMSampleBufferRef)sampleBuffer;
- (void) shutdown;

@end
