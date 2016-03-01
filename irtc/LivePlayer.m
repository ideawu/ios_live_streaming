#import <AVFoundation/AVFoundation.h>
#import "LivePlayer.h"
#import "LiveClipReader.h"
#import "AudioPlayer.h"

@interface Clock : NSObject{
	double _tick_zero;
	double _tick_last;
	double _speed;
	double _change_speed_tick;
}
@property (nonatomic, readonly) double now;
// default: 1.0
@property (nonatomic) double speed;
@end

@implementation Clock
- (id)init{
	self = [super init];
	_speed = 1;
	[self reset];
	return self;
}

- (void)reset{
	_now = -1;
	_tick_zero = -1;
}

- (double)speed{
	return _speed;
}

- (void)setSpeed:(double)speed{
	if(speed < 0){
		return;
	}
	_speed = speed;
	_change_speed_tick = _tick_last;
}

- (void)tick:(double)real_tick{
	_tick_last = real_tick;
	if(_tick_zero == -1){
		_tick_zero = real_tick;
		_change_speed_tick = _tick_last;
	}
	double df = _speed * (real_tick - _change_speed_tick);
	_now =  df + (_change_speed_tick - _tick_zero);
}
@end


@interface LivePlayer (){
#if TARGET_OS_IPHONE
	CADisplayLink *_displayLink;
#else
	CVDisplayLinkRef _displayLink;
#endif
	
	dispatch_queue_t _processQueue;
	NSMutableArray *_items;
	Clock *_clock;
	double first_time;
	double last_time_s;
	double last_time_e;
	
	int _file_name_seq;
}
@property CALayer *layer;
@property AudioPlayer *audio;
@end

@implementation LivePlayer

+ (LivePlayer *)playerWithCALayer:(CALayer *)layer{
	LivePlayer *ret = [[LivePlayer alloc] initWithCALayer:layer];
	return ret;
}


- (id)init{
	self = [super init];
	
	_file_name_seq = 0;
	_items = [[NSMutableArray alloc] init];

	return self;
}

- (id)initWithCALayer:(CALayer *)layer{
	self = [self init];
	_layer = layer;
	return self;
}

- (void)setSpeed:(double)speed{
	_clock.speed = speed;
}

- (void)play{
	if(!_clock){
		_clock = [[Clock alloc] init];
		_audio = [[AudioPlayer alloc] init];
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

- (void)addMovieData:(NSData *)data{
	[self addMovieData:data originalPath:nil];
}

- (void)addMovieData:(NSData *)data originalPath:(NSString *)originalPath{
	dispatch_async(_processQueue, ^{
		int pid = [NSProcessInfo processInfo].processIdentifier;
		_file_name_seq = (_file_name_seq + 1) % 99;
		NSString *ext = @"mov";
		if(originalPath){
			NSArray *ps = [originalPath componentsSeparatedByString:@"."];
			ext = ps.lastObject;
		}
		NSString *name = [NSString stringWithFormat:@"%@/p-%d-%03d.%@",
						  NSTemporaryDirectory(), pid, _file_name_seq, ext];
		if([[NSFileManager defaultManager] fileExistsAtPath:name]){
			[[NSFileManager defaultManager] removeItemAtPath:name error:nil];
		}
		[data writeToFile:name atomically:YES];
		
		[self addMovieFile:name];
	});
}

- (void)addMovieFile:(NSString *)localFilePath{
	dispatch_async(_processQueue, ^{
		//NSLog(@"add movie file: %@", localFilePath.lastPathComponent);
		LiveClipReader *item = [LiveClipReader clipReaderWithURL:[NSURL fileURLWithPath:localFilePath]];
		//NSLog(@"%@", localFilePath.lastPathComponent);
		[_items addObject:item];
	});
}

- (void)removeAllItems{
	dispatch_async(_processQueue, ^{
		[_items removeAllObjects];
	});
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
		[(__bridge LivePlayer *)displayLinkContext tickCallback:time];
		return kCVReturnSuccess;
	}
#endif

- (void)tickCallback:(double)tick{
	dispatch_async(_processQueue, ^{
		[self displayFrameForTickTime:tick];
	});
}

- (void)readAllAudioSamples:(LiveClipReader *)reader{
	NSLog(@"read all audio samples");
	while(1){
		CMSampleBufferRef s = [reader nextAudioSampleBuffer];
		if(!s){
			break;
		}
		[_audio appendSampleBuffer:s];
	}
}

// TODO: 在主线程进行 IO 不是个好主意, 需要优化
- (void)displayFrameForTickTime:(double)tick{
	while(1){
		LiveClipReader *reader = _items.firstObject;
		if(!reader){
			return;
		}
		
		[_clock tick:tick];
		if(_clock.now == 0){
			first_time = reader.startTime;
			last_time_e = reader.startTime;
		}

		if(!reader.isReading){
			// 将影片时间转成时钟时间
			double clip_s = reader.startTime - first_time;
			double clip_e = reader.endTime - first_time;

			double time_gap = reader.startTime - last_time_e;
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
			if(delay > reader.duration/2){
				// drop delayed clip
				NSLog(@"drop delayed %.3f s clip[%.3f~%.3f]", delay, clip_s, clip_e);
				last_time_s = reader.startTime;
				last_time_e = reader.startTime;
				[_items removeObjectAtIndex:0];
				continue;
			}
			
			last_time_s = reader.startTime;
			last_time_e = reader.endTime;

			NSLog(@"start session at %.3f, clip[%.3f~%.3f], delay: %.3f", _clock.now, clip_s, clip_e, delay);
			[reader startSessionAtSourceTime:_clock.now];
			
			[self readAllAudioSamples:reader];
		}

		CGImageRef frame;
		frame = [reader copyNextFrameForTime:_clock.now];
		if(!frame){
			if(reader.isReading){
				return;
			}else{
				// switch reader
				NSLog(@"stop session at %.3f", _clock.now);
				[_items removeObjectAtIndex:0];
				continue;
			}
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			self.layer.contents = (__bridge id)(frame);
			CFRelease(frame);
		});
		
		return;
	}
}

@end
