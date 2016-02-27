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
	
	double last_clip_end_time;
	double _nextTick;
	double _start_tick;
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

- (void)displayFrameForTickTime:(double)time{
	while(1){
		LiveClipReader *reader = _items.firstObject;
		if(!reader){
			_nextTick = time;
			if(last_clip_end_time > 0){
				NSLog(@"no reader");
			}
			return;
		}
		if(!reader.isReading){
			double diff = reader.startTime - last_clip_end_time;
			double diff2 = time - _nextTick;
			//NSLog(@"diff: %.3f, %.3f %.3f %.3f", diff, diff2, reader.startTime, last_clip_end_time);
			double buffer_time = 0.1;
			if(diff > buffer_time || diff < -buffer_time || diff2 > buffer_time || diff2 < -buffer_time){
				NSLog(@"reset tick %.3f => %.3f", _nextTick, time+buffer_time);
				_nextTick = time + buffer_time;
			}
			last_clip_end_time = reader.endTime;
			
			NSLog(@"start session at %.3f, tick: %.3f", _nextTick, time);
			[reader startSessionAtSourceTime:_nextTick];
		}
		
		CGImageRef frame;
		frame = [reader copyNextFrameForTime:time];
		if(!frame){
			if(reader.isReading){
				return;
			}else{
				// switch reader
				NSLog(@"stop session at %.3f", time);
				[_items removeObjectAtIndex:0];
				continue;
			}
		}
		
		// TODO: 当delay过大时, 应丢弃一些

		_nextTick = time + reader.frameDuration;
		self.layer.contents = (__bridge id)(frame);
		CFRelease(frame);
		
		return;
	}
}

@end
