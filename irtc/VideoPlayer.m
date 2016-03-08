//
//  VideoPlayer.m
//  irtc
//
//  Created by ideawu on 16-3-6.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import "VideoPlayer.h"
#import "VideoDecoder.h"
#import "PlayerState.h"

@interface VideoPlayer(){
#if TARGET_OS_IPHONE
	CADisplayLink *_displayLink;
#else
	CVDisplayLinkRef _displayLink;
#endif
	double first_time;
	double last_time_s;
	double last_time_e;

	NSMutableArray *_items;
	NSMutableArray *_frames; // decompressed frames

	BOOL _started;
	VideoDecoder *_decoder;

	dispatch_queue_t _processQueue;
}
@property PlayerState *state;
@end


@implementation VideoPlayer

- (id)init{
	self = [super init];
	_started = NO;
	_items = [[NSMutableArray alloc] init];
	_frames = [[NSMutableArray alloc] init];
	_state = [[PlayerState alloc] init];
	return self;
}

- (void)addClip:(VideoClip *)clip{
	dispatch_async(_processQueue, ^{
		[_items addObject:clip];
	});
}

- (double)speed{
	return _state.speed;
}

- (void)setSpeed:(double)speed{
	_state.speed = speed;
}

- (void)play{
	if(!_processQueue){
		_processQueue = dispatch_queue_create("player queue", DISPATCH_QUEUE_SERIAL);

		_decoder = [[VideoDecoder alloc] init];
		__weak typeof(self) me = self;
		[_decoder setCallback:^(CVImageBufferRef imageBuffer) {
			[me onDecompressFrame:imageBuffer];
		}];
		
		[self setupDisplayLink];
	}
	[self startDisplayLink];
	NSLog(@"starting...");
	[_state pause];
}

- (void)pause{
	
}

#pragma mark - CADisplayLink/CVDisplayLinkRef Callback

- (void)setupDisplayLink{
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

- (void)startDisplayLink{
#if TARGET_OS_IPHONE
	[_displayLink setPaused:NO];
#else
	CVDisplayLinkStart(_displayLink);
#endif
}

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

- (void)onDecompressFrame:(CVImageBufferRef)imageBuffer{
	CFRetain(imageBuffer);
	dispatch_async(_processQueue, ^{
		[_frames addObject:(__bridge id)(imageBuffer)];
		//NSLog(@"decompressed frames: %d", (int)_frames.count);
	});
}

// CVImageBufferRef 即是 CVPixelBufferRef
- (CGImageRef)pixelBufferToImageRef:(CVImageBufferRef)imageBuffer{
	CVPixelBufferLockBaseAddress(imageBuffer, 0);
	uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
	size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
	size_t width = CVPixelBufferGetWidth(imageBuffer);
	size_t height = CVPixelBufferGetHeight(imageBuffer);
	
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(baseAddress,
												 width, height,
												 8, bytesPerRow,
												 colorSpace,
												 kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
	CGImageRef image = NULL;
	if(context){
		image = CGBitmapContextCreateImage(context);
	}
	CGContextRelease(context);
	CGColorSpaceRelease(colorSpace);
	return image;
}

- (void)displayFrameForTickTime:(double)tick{
	while(1){
		VideoClip *clip = _items.firstObject;
		
		if(!_decoder.isReadyForFrame){
			if(!clip){
				return;
			}
			if(clip.sps){
				NSLog(@"init sps and pps");
				[_decoder setSps:clip.sps pps:clip.pps];
			}else{
				NSLog(@"not started, expecting sps and pps, drop clip");
				[_items removeObjectAtIndex:0];
			}
			continue;
		}
		
		if(clip){
			_state.frameDuration = clip.frameDuration;
		}
		
		[_state tick:tick];
		
		if(_frames.count >= 5){
			if(!_state.isPlaying){
				NSLog(@"start playing");
				[_state resume];
			}
			// TODO: 如果缓冲数据太多, 丢弃一些
		}
		if(_frames.count < 10){
			if(clip){
				double pts;
				NSData *frame = [clip nextFrame:&pts];
				if(!frame){
					[_items removeObjectAtIndex:0];
				}else{
					[_decoder appendFrame:frame];
				}
			}
		}
		
		if(_state.readyForNextFrame){
			if(_frames.count == 0){
				NSLog(@"buffering...");
				[_state pause];
			}else{
//				NSLog(@"  time: %.3f expect: %.3f, delay: %+.3f, frameDuration: %.3f",
//					  _state.time, _state.nextFrameTime, _state.delay, _state.frameDuration);
				[_state nextFrame];
				
				CVImageBufferRef imageBuffer = (__bridge CVImageBufferRef)(_frames.firstObject);
				[_frames removeObjectAtIndex:0];
				CGImageRef image = [self pixelBufferToImageRef:imageBuffer];
				if(!image){
					CFRelease(imageBuffer);
				}else{
					dispatch_async(dispatch_get_main_queue(), ^{
						self.layer.contents = (__bridge id)(image);
						CFRelease(image);
					});
				}
			}
		}
		
		return;
		
		
		
//		if(_clock.time == 0){
//			first_time = item.clip.startTime;
//			last_time_e = item.clip.startTime;
//		}
//		
//		if(!item.isReading){
//			// 将影片时间转成时钟时间
//			double clip_s = item.clip.startTime - first_time;
//			double clip_e = item.clip.endTime - first_time;
//			
//			double time_gap = item.clip.startTime - last_time_e;
//			if(time_gap > 5 || time_gap < -5){
//				NSLog(@"===== reset clock =====");
//				[_clock reset];
//				continue;
//			}
//			if(time_gap >= -5 && time_gap < 0){
//				// drop mis-order clip
//				NSLog(@"drop mis-order clip[%.3f~%.3f]", clip_s, clip_e);
//				[_items removeObjectAtIndex:0];
//				continue;
//			}
//			
//			double delay = _clock.time - clip_s;
//			if(delay > item.clip.duration/2){
//				// drop delayed clip
//				NSLog(@"drop delayed %.3f s clip[%.3f~%.3f]", delay, clip_s, clip_e);
//				last_time_s = item.clip.startTime;
//				last_time_e = item.clip.startTime;
//				[_items removeObjectAtIndex:0];
//				continue;
//			}
//			
//			last_time_s = item.clip.startTime;
//			last_time_e = item.clip.endTime;
//			
//			double stime = _clock.time - delay;
//			NSLog(@"start session at %.3f, clip[%.3f~%.3f], delay: %.3f, time: %.3f", stime, clip_s, clip_e, delay, _clock.time);
//			//NSLog(@"start session at %.3f, clip[%.3f~%.3f], delay: %.3f", stime, clip_s, clip_e, delay);
//			[item startSessionAtSourceTime:stime];
//		}
//		
//		if(![item hasNextFrameForTime:_clock.time]){
//			return;
//		}
//		
//		double expect = 0;
//		expect = item.clip.nextFramePTS - item.clip.startTime + item.sessionStartTime;
//		
//		NSData *frame = [item nextFrame];
//		if(!frame || item.isCompleted){
//			NSLog(@"stop session at %.3f", _clock.time);
//			[_items removeObjectAtIndex:0];
//			continue;
//		}
//		
//		uint8_t *pNal = (uint8_t*)[frame bytes];
//		int nal_ref_idc = pNal[0] & 0x60;
//		int nal_type = pNal[0] & 0x1f;
//		// TODO: 到底应该怎么处理 SEI?
//		if (nal_ref_idc == 0 && nal_type == 6) { // SEI
//			//NSLog(@"ignore SEI");
//			continue;
//		}
//
////		double delay = _clock.time - expect;
////		NSLog(@"time: %.3f, expect: %.3f, delay: %+.3f", _clock.time, expect, delay);
//
//		CMSampleBufferRef sampleBuffer = [_decoder processFrame:frame];
//		if(sampleBuffer){
//			dispatch_async(dispatch_get_main_queue(), ^{
//				[_videoLayer enqueueSampleBuffer:sampleBuffer];
//				CFRelease(sampleBuffer);
//			});
//		}
//
//		return;
	}
}

@end
