
#import <AVFoundation/AVFoundation.h>
#import "LivePlayer.h"
#import "LiveClipReader.h"

@interface LivePlayer (){
	dispatch_queue_t _queue;
	NSMutableArray *_items;
	
	AVAssetReader *_assetReader;
	BOOL _animating;
	int seq;
	int currentItemIndex;
	
#if !TARGET_OS_IPHONE
	CVDisplayLinkRef _displayLink;
#endif
	double _nextTime;
}
@property CALayer *layer;
@property NSInteger readIdx;
- (void)displayFrameForTime:(double)time;
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

	CVReturn ret;
	ret = CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
	ret = CVDisplayLinkSetOutputCallback(_displayLink, displayLinkCallback, (__bridge void *)(self));
	ret = CVDisplayLinkStart(_displayLink);
	
//	_displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkCallback:)];
//	[_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
//	[_displayLink setPaused:YES];

	return self;
}

- (id)initWithCALayer:(CALayer *)layer{
	self = [self init];
	_layer = layer;
	return self;
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
		LiveClipReader *item = [LiveClipReader clipReaderWithURL:[NSURL fileURLWithPath:localFilePath]];
		dispatch_async(dispatch_get_main_queue(), ^{
			[_items addObject:item];
		});
	});
}

- (void)removeAllItems{
	[_items removeAllObjects];
	dispatch_async(_queue, ^{
		_animating = NO;
	});
}

#pragma mark - CADisplayLink Callback

static CVReturn displayLinkCallback(CVDisplayLinkRef displayLink, const CVTimeStamp *now,
									const CVTimeStamp *outputTime, CVOptionFlags flagsIn,
									CVOptionFlags *flagsOut, void *displayLinkContext)
{
	double time = outputTime->hostTime/1000.0/1000.0/1000.0;
	time *= 0.5;
	LivePlayer *player = (__bridge LivePlayer *)displayLinkContext;
	dispatch_async(dispatch_get_main_queue(), ^{
		[player displayFrameForTime:time];
	});
	return kCVReturnSuccess;
}

//
//- (void)displayLinkCallback:(CADisplayLink *)sender{
//	
//}

- (void)displayFrameForTime:(double)time{
	while(1){
		LiveClipReader *reader = _items.firstObject;
		if(!reader){
			return;
		}
		if(!reader.isReading){
			// TODO: TESTING
			NSLog(@"start reader");
			[reader startSessionAtSourceTime:_nextTime];
		}
		
		CGImageRef frame;
		frame = [reader copyNextFrameForTime:time];
		if(!frame){
			if(reader.isReading){
				return;
			}else{
				// switch reader
				NSLog(@"switch reader");
				[_items removeObjectAtIndex:0];
				continue;
			}
		}
		
		// TODO: if delay too much, skip frame?

		_nextTime = time + reader.frameDuration;
		self.layer.contents = (__bridge id)(frame);
		CFRelease(frame);
		return;
	}
}

@end
