//
//  VideoPlayer.m
//  irtc
//
//  Created by ideawu on 16-3-6.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import "VideoPlayer.h"
#import "VideoDecoder.h"
#import "Clock.h"
#import "PlayerItem.h"

@interface VideoPlayer(){
#if TARGET_OS_IPHONE
	CADisplayLink *_displayLink;
#else
	CVDisplayLinkRef _displayLink;
#endif
	Clock *_clock;
	double first_time;
	double last_time_s;
	double last_time_e;

	NSMutableArray *_items;

	BOOL _started;
	VideoDecoder *_decoder;

	dispatch_queue_t _processQueue;
}
@end


@implementation VideoPlayer

- (id)init{
	self = [super init];
	_started = NO;
	_decoder = [[VideoDecoder alloc] init];
	_items = [[NSMutableArray alloc] init];
	return self;
}

- (void)addClip:(VideoClip *)clip{
	PlayerItem *item = [[PlayerItem alloc] init];
	item.clip = clip;
	dispatch_async(_processQueue, ^{
		[_items addObject:item];
	});
}

- (void)play{
	if(!_clock){
		_clock = [[Clock alloc] init];
		_processQueue = dispatch_queue_create("liveavplayer queue", DISPATCH_QUEUE_SERIAL);
		
#if TARGET_OS_IPHONE
		_displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkCallback:)];
		[_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
		[_displayLink setPaused:YES];
#else
		CVReturn ret;
		ret = CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
		ret = CVDisplayLinkSetOutputCallback(_displayLink, displayLinkCallback, (__bridge void *)(self));
#endif
	}
	
#if TARGET_OS_IPHONE
	[_displayLink setPaused:NO];
#else
	CVDisplayLinkStart(_displayLink);
#endif
}

#pragma mark - CADisplayLink/CVDisplayLinkRef Callback

#if TARGET_OS_IPHONE
- (void)displayLinkCallback:(CADisplayLink *)sender{
	double time = _displayLink.timestamp;
	[self tickCallback:time];
}
#else
static CVReturn displayLinkCallback(CVDisplayLinkRef displayLink, const CVTimeStamp *now,
									const CVTimeStamp *outputTime, CVOptionFlags flagsIn,
									CVOptionFlags *flagsOut, void *displayLinkContext)
{
	double time = outputTime->hostTime/1000.0/1000.0/1000.0;
	[(__bridge VideoPlayer *)displayLinkContext tickCallback:time];
	return kCVReturnSuccess;
}
#endif

- (void)tickCallback:(double)tick{
	dispatch_async(_processQueue, ^{
		[self displayFrameForTickTime:tick];
	});
}
// TODO: 在主线程进行 IO 不是个好主意, 需要优化
- (void)displayFrameForTickTime:(double)tick{
	while(1){
		PlayerItem *item = _items.firstObject;
		if(!item){
			return;
		}
		
		if(!_started){
			if(item.clip.sps){
				_started = YES;
				NSLog(@"init sps and pps");
				[_decoder setSps:item.clip.sps pps:item.clip.pps];
			}else{
				NSLog(@"not started, expecting sps and pps");
				return;
			}
		}
		
		[_clock tick:tick];
		if(_clock.now == 0){
			first_time = item.clip.startTime;
			last_time_e = item.clip.startTime;
		}
		
		if(!item.isReading){
			// 将影片时间转成时钟时间
			double clip_s = item.clip.startTime - first_time;
			double clip_e = item.clip.endTime - first_time;
			
			double time_gap = item.clip.startTime - last_time_e;
			if(time_gap > 5 || time_gap < -5){
				NSLog(@"===== reset clock =====");
				[_clock reset];
				continue;
			}
			if(time_gap >= -5 && time_gap < 0){
				// drop mis-order clip
				NSLog(@"drop mis-order clip[%.3f~%.3f]", clip_s, clip_e);
				[_items removeObjectAtIndex:0];
				continue;
			}
			
			double delay = _clock.now - clip_s;
			if(delay > item.clip.duration/2){
				// drop delayed clip
				NSLog(@"drop delayed %.3f s clip[%.3f~%.3f]", delay, clip_s, clip_e);
				last_time_s = item.clip.startTime;
				last_time_e = item.clip.startTime;
				[_items removeObjectAtIndex:0];
				continue;
			}
			
			last_time_s = item.clip.startTime;
			last_time_e = item.clip.endTime;
			
			double stime = _clock.now - delay;
			NSLog(@"start session at %.3f, clip[%.3f~%.3f], delay: %.3f, now: %f", stime, clip_s, clip_e, delay, _clock.now);
			//NSLog(@"start session at %.3f, clip[%.3f~%.3f], delay: %.3f", stime, clip_s, clip_e, delay);
			[item startSessionAtSourceTime:stime];
		}
		
		if(![item hasNextFrameForTime:_clock.now]){
			return;
		}
		
		double expect = item.clip.nextFramePTS - item.clip.startTime + item.sessionStartTime;
		
		NSData *frame = [item nextFrame];
		if(!frame || item.isCompleted){
			NSLog(@"stop session at %.3f", _clock.now);
			[_items removeObjectAtIndex:0];
			continue;
		}
		
		uint8_t *pNal = (uint8_t*)[frame bytes];
		int nal_ref_idc = pNal[0] & 0x60;
		int nal_type = pNal[0] & 0x1f;
		// TODO: 到底应该怎么处理 SEI?
		if (nal_ref_idc == 0 && nal_type == 6) { // SEI
			NSLog(@"ignore SEI");
			continue;
		}

		double delay = _clock.now - expect;
		NSLog(@"time: %.3f, expect: %.3f, delay: %+.3f", _clock.now, expect, delay);

		CMSampleBufferRef sampleBuffer = [_decoder processFrame:frame];
		if(sampleBuffer){
			dispatch_async(dispatch_get_main_queue(), ^{
				[_videoLayer enqueueSampleBuffer:sampleBuffer];
				CFRelease(sampleBuffer);
			});
		}

		return;
	}
}

@end
