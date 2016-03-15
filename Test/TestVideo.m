//
//  TestVideo.m
//  irtc
//
//  Created by ideawu on 16-3-13.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import "TestVideo.h"
#import "VideoReader.h"
#import "VideoEncoder.h"
#import "VideoDecoder.h"

@interface TestVideo(){
	VideoReader *reader;
	VideoEncoder *_encoder;
	VideoDecoder *_decoder;

	VideoEncoder *_encoder2;
}
@end


@implementation TestVideo

- (id)init{
	self = [super init];
	[self run];
	return self;
}

- (void)run{
	_encoder2 = [[VideoEncoder alloc] init];
	[_encoder2 start:^(NSData *nalu, double pts, double duration) {
		log_debug(@"encoder 2, %d bytes", (int)nalu.length);
	}];

	_decoder = [[VideoDecoder alloc] init];
	[_decoder start:^(CVPixelBufferRef pixelBuffer, double pts, double duration) {
		log_debug(@"decoded, pts: %f, duration: %f", pts, duration);
		[_encoder2 encodePixelBuffer:pixelBuffer pts:pts duration:duration];
	}];

	_encoder = [[VideoEncoder alloc] init];
	[_encoder start:^(NSData *nalu, double pts, double duration) {
		log_debug(@"encoded, pts: %f, duration: %f, %d bytes", pts, duration, (int)nalu.length);
		if(!_decoder.isReadyForFrame && _encoder.sps){
			log_debug(@"init decoder");
			[_decoder setSps:_encoder.sps pps:_encoder.pps];
		}
		[_decoder decode:nalu pts:pts duration:duration];
	}];

	NSString *file = [NSHomeDirectory() stringByAppendingFormat:@"/Downloads/m1.mp4"];
	reader = [[VideoReader alloc] initWithFile:file];
	CMSampleBufferRef sampleBuffer;
	while(1){
		sampleBuffer = [reader nextSampleBuffer];
		if(!sampleBuffer){
			break;
		}

		[_encoder encodeSampleBuffer:sampleBuffer];

		CFRelease(sampleBuffer);
		usleep(30 * 1000);
	}
}

@end
