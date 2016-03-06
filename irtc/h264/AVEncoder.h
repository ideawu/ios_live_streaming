//
//  AVEncoder.h
//  Encoder Demo
//
//  Created by Geraint Davies on 14/01/2013.
//  Copyright (c) 2013 GDCL http://www.gdcl.co.uk/license.htm
//

#import <AVFoundation/AVFoundation.h>
#import "sys/stat.h"

typedef int (^encoder_handler_t)(NSArray* frames, double pts);
typedef int (^param_handler_t)(NSData* sps, NSData *pps);

@interface AVEncoder : NSObject

@property int bitrate;

+ (AVEncoder*) encoderForHeight:(int)height andWidth:(int)width bitrate:(int)bitrate;

- (void) encodeWithBlock:(encoder_handler_t) block onParams: (param_handler_t) paramsHandler;
- (void) encodeFrame:(CMSampleBufferRef) sampleBuffer;
- (NSData*) getConfigData;
- (void) shutdown;


@property (readonly, atomic) int bitspersecond;

@end
