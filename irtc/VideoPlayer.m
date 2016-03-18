//
//  VideoPlayer.m
//  irtc
//
//  Created by ideawu on 16-3-6.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import "VideoPlayer.h"
#import "VideoDecoder.h"
#import "VideoPlayerState.h"

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
@property VideoPlayerState *state;
@end


@implementation VideoPlayer

- (id)init{
	self = [super init];
	_started = NO;
	_items = [[NSMutableArray alloc] init];
	_frames = [[NSMutableArray alloc] init];
	_state = [[VideoPlayerState alloc] init];
	_processQueue = dispatch_queue_create("player queue", DISPATCH_QUEUE_SERIAL);
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
	if(!_decoder){
		_decoder = [[VideoDecoder alloc] init];
		__weak typeof(self) me = self;
		[_decoder start:^(CVImageBufferRef imageBuffer, double pts, double duration) {
			[me onDecompressFrame:imageBuffer pts:pts];
		}];
		
		[self setupDisplayLink];
	}
	[self startDisplayLink];
	log_debug(@"starting...");
	[_state start];
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
									CVOptionFlags *flagsOut, void *displayLinkContext){
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

- (void)onDecompressFrame:(CVImageBufferRef)imageBuffer pts:(double)pts{
	CFRetain(imageBuffer);
	dispatch_async(_processQueue, ^{
		[_frames addObject:@[(__bridge id)(imageBuffer), @(pts)]];
		//NSLog(@"decompressed frames: %d", (int)_frames.count);
	});
}

- (void)prepareFrames{
	LOG_FIRST_RUN();
	dispatch_async(_processQueue, ^{
		VideoClip *clip = _items.firstObject;
		if(!clip){
			return;
		}
		for(int i=0; i<3; i++){
			double pts;
			NSData *frame = [clip nextFrame:&pts];
			if(!frame){
				[_items removeObjectAtIndex:0];
				break;
			}else{
				[_decoder decode:frame pts:pts];
			}
		}
	});
}

- (void)displayFrameForTickTime:(double)tick{
	while(1){
		// TODO: 如果clip数量太多, 应该丢弃一些

		VideoClip *clip = _items.firstObject;
		
		if(!_decoder.isReadyForFrame){
			if(!clip){
				return;
			}
			if(clip.sps){
				log_debug(@"player init decoder sps and pps");
				[_decoder setSps:clip.sps pps:clip.pps];
			}else{
				NSLog(@"not started, expecting sps and pps, drop clip");
				[_items removeObjectAtIndex:0];
			}
			continue;
		}
		if(clip){
			_state.frameDuration = clip.frameDuration;
			if(_frames.count < 10){
				[self prepareFrames];
			}
		}
		
		// 更新时钟
		[_state tick:tick];

		if(_frames.count >= 5){
			if(_state.isStarting){
				log_debug(@"started at %f", _state.time);
				[_state play];
			}
			if(_state.isPaused){
				NSLog(@"resume at %f", _state.time);
				[_state play];
			}
		}
		if(!_state.isReadyForNextFrame){
			return;
		}
		
		if(_frames.count == 0){
			NSLog(@"pause at %f", _state.time);
			[_state pause];
			return;
		}

		NSArray *arr = _frames.firstObject;
		CVImageBufferRef imageBuffer = (__bridge CVImageBufferRef)(arr.firstObject);
		double pts = [(NSNumber *)arr.lastObject doubleValue];
		[_frames removeObjectAtIndex:0];

		// TODO: 如果太超前或者太落后, 需要重置 _state
		if(ABS(pts - _state.pts) > 15){
			NSLog(@"reset state");
			[_state reset];
		}
//		log_debug(@"  time: %.3f expect: %.3f, delay: %+.3f, duration: %.3f",
//			  _state.time, _state.nextFrameTime, _state.delay, _state.frameDuration);

		[_state displayFramePTS:pts];
		[self displayPixelBuffer:imageBuffer];
		return;
	}
}

- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer{
	LOG_FIRST_RUN();
	CGImageRef image = [self pixelBufferToImageRef:pixelBuffer];
	if(!image){
		CFRelease(pixelBuffer);
	}else{
		dispatch_async(dispatch_get_main_queue(), ^{
			self.layer.contents = (__bridge id)(image);
			CFRelease(image);
		});
	}

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
												 kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst
												 );
	CGImageRef image = NULL;
	if(context){
		image = CGBitmapContextCreateImage(context);
	}
	CGContextRelease(context);
	CGColorSpaceRelease(colorSpace);
	return image;
}

@end
