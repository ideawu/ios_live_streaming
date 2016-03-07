//
//  VideoPlayer.m
//  irtc
//
//  Created by ideawu on 16-3-6.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import "VideoPlayer.h"
#import "VideoDecoder.h"

@interface VideoPlayer(){
	BOOL _started;
	VideoDecoder *_decoder;
}
@end


@implementation VideoPlayer

- (id)init{
	self = [super init];
	_started = NO;
	_decoder = [[VideoDecoder alloc] init];
	return self;
}

- (void)play{
	
}

- (void)addClip:(VideoClip *)clip{
	if(!_started){
		if(clip.sps){
			_started = YES;
			[_decoder setSps:clip.sps pps:clip.pps];
		}else{
			NSLog(@"not started, expecting sps and pps");
			return;
		}
	}

	// TODO:
	while(1){
		double pts = 0;
		NSData *frame = [clip nextFrame:&pts];
		if(!frame){
			break;
		}
		CMSampleBufferRef sampleBuffer = [_decoder processFrame:frame];
		if(sampleBuffer){
			double delay = pts - clip.startTime;
			dispatch_async(dispatch_get_main_queue(), ^{
				[_videoLayer performSelector:@selector(enqueueSampleBuffer:)
								  withObject:(__bridge id)(sampleBuffer)
								  afterDelay:delay];
				CFRelease(sampleBuffer);
			});
		}
	}
}


@end
