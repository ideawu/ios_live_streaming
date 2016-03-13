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
}
@end


@implementation TestVideo

- (id)init{
	self = [super init];
	[self run];
	return self;
}

- (void)run{
	_decoder = [[VideoDecoder alloc] init];
	[_decoder start:^(CVImageBufferRef imageBuffer, double pts) {
		log_debug(@"decoded, pts: %f", pts);
	}];

	_encoder = [[VideoEncoder alloc] init];
	[_encoder start:^(NSData *h264, double pts, double duration) {
		log_debug(@"encoded %d bytes, pts: %f, duration: %f", (int)h264.length, pts, duration);
		if(!_decoder.isReadyForFrame && _encoder.sps){
			log_debug(@"init decoder");
			[_decoder setSps:_encoder.sps pps:_encoder.pps];
		}
		[_decoder decode:h264 pts:pts];
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
		usleep(100 * 1000);
	}
}

@end
