#import <AVFoundation/AVFoundation.h>
#import "LivePlayer.h"
#import "LiveClipReader.h"

@interface LivePlayer (){
	dispatch_queue_t _queue;
	NSMutableArray *_items;
	int seq;
	
#if TARGET_OS_IPHONE
	CADisplayLink *_displayLink;
#else
	CVDisplayLinkRef _displayLink;
#endif
	
	double _start_tick;

	double first_time;
	double first_tick;
	double last_time_s;
	double last_time_e;
	double last_tick;
}
@property CALayer *layer;
@property NSInteger readIdx;
@end

@implementation LivePlayer

+ (LivePlayer *)playerWithCALayer:(CALayer *)layer{
	LivePlayer *ret = [[LivePlayer alloc] initWithCALayer:layer];
	return ret;
}


- (id)init{
	self = [super init];
	_queue = dispatch_queue_create("liveavplayer queue", DISPATCH_QUEUE_SERIAL);
	_items = [[NSMutableArray alloc] init];
	_readIdx = 0;

#if TARGET_OS_IPHONE
	_displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkCallback:)];
	[_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	[_displayLink setPaused:YES];
#else
	CVReturn ret;
	ret = CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
	ret = CVDisplayLinkSetOutputCallback(_displayLink, displayLinkCallback, (__bridge void *)(self));
#endif

	return self;
}

- (id)initWithCALayer:(CALayer *)layer{
	self = [self init];
	_layer = layer;
	return self;
}

- (void)play{
#if TARGET_OS_IPHONE
	[_displayLink setPaused:NO];
#else
	ret = CVDisplayLinkStart(_displayLink);
#endif
}

- (void)addMovieData:(NSData *)data{
	[self addMovieData:data originalPath:nil];
}

- (void)addMovieData:(NSData *)data originalPath:(NSString *)originalPath{
	dispatch_async(_queue, ^{
		seq = (seq + 1) % 99;
		NSString *ext = @"mov";
		if(originalPath){
			NSArray *ps = [originalPath componentsSeparatedByString:@"."];
			ext = ps.lastObject;
		}
		NSString *filename = [NSString stringWithFormat:@"%@/download_%03d.%@", NSTemporaryDirectory(), seq, ext];
		if([[NSFileManager defaultManager] fileExistsAtPath:filename]){
			[[NSFileManager defaultManager] removeItemAtPath:filename error:nil];
		}
		[data writeToFile:filename atomically:YES];
		
		[self addMovieFile:filename];
	});
}

- (void)addMovieFile:(NSString *)localFilePath{
	dispatch_async(_queue, ^{
		//NSLog(@"add movie file: %@", localFilePath.lastPathComponent);
		LiveClipReader *item = [LiveClipReader clipReaderWithURL:[NSURL fileURLWithPath:localFilePath]];
		//NSLog(@"%@", localFilePath.lastPathComponent);
		dispatch_async(dispatch_get_main_queue(), ^{
			[_items addObject:item];
		});
	});
}

- (void)removeAllItems{
	[_items removeAllObjects];
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
		LivePlayer *player = (__bridge LivePlayer *)displayLinkContext;
		[player tickCallback:time];
		return kCVReturnSuccess;
	}
#endif

- (void)tickCallback:(double)time{
	if(_start_tick <= 0){
		_start_tick = time;
	}
	time = time - _start_tick;
	
	double speed = 1;
	time *= speed;
	LivePlayer *player = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		[player displayFrameForTickTime:time];
	});
}

- (void)displayFrameForTickTime:(double)tick{
	while(1){
		LiveClipReader *reader = _items.firstObject;
		if(!reader){
			return;
		}

		if(first_time == 0){
			NSLog(@"reset tick %.3f => %.3f", first_tick, tick);
			first_tick = tick;
			first_time = reader.startTime;
			last_time_s = reader.startTime;
			last_time_e = reader.startTime;
		}
		// 相对于时钟零点
		double now_tick = tick - first_tick;

		if(!reader.isReading){
			// 相对于影片零点
			double clip_s = reader.startTime - first_time;
			double clip_e = reader.endTime - first_time;

			double time_gap = reader.startTime - last_time_e;
			if(time_gap > 5 || time_gap < -5){
				// reset timers
				first_time = 0;
				continue;
			}
			if(time_gap >= -5 && time_gap < 0){
				// drop mis-order clip
				NSLog(@"drop mis-order clip[%.3f~%.3f]", clip_s, clip_e);
				[_items removeObjectAtIndex:0];
				continue;
			}

			double delay = now_tick - clip_s;
			if(delay > reader.duration/2){
				// drop delayed clip
				NSLog(@"drop delayed %.3f s clip[%.3f~%.3f]", delay, clip_s, clip_e);
				last_time_s = reader.startTime;
				last_time_e = reader.startTime;
				[_items removeObjectAtIndex:0];
				continue;
			}

			NSLog(@"start session at %.3f, clip[%.3f~%.3f], delay: %.3f", now_tick, clip_s, clip_e, delay);
			[reader startSessionAtSourceTime:clip_s];
			last_time_s = reader.startTime;
			last_time_e = reader.endTime;
		}
		last_tick = now_tick;

		CGImageRef frame;
		frame = [reader copyNextFrameForTime:now_tick];
		if(!frame){
			if(reader.isReading){
				return;
			}else{
				// switch reader
				NSLog(@"stop session at %.3f", now_tick);
				[_items removeObjectAtIndex:0];
				continue;
			}
		}

		self.layer.contents = (__bridge id)(frame);
		CFRelease(frame);
		
		return;
	}
}

@end
