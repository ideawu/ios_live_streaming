//
//  PlayerController.m
//  VideoTest
//
//  Created by ideawu on 12/11/15.
//  Copyright © 2015 ideawu. All rights reserved.
//

#import "PlayerController.h"
#import <AVFoundation/AVFoundation.h>
#import "LivePlayer.h"

@interface PlayerController (){
	BOOL _playing;
	dispatch_queue_t _downloadQueue;
	NSMutableArray *_downloadList;
	NSMutableArray *_historyList;
}
@property AVPlayerLayer *playerLayer;
@property AVQueuePlayer *player;
@property AVPlayerItem *lastItem;
@property LivePlayer *livePlayer;
@end

@implementation PlayerController

static int num = 0;

- (void)windowDidLoad {
    [super windowDidLoad];
	_videoView.layer.backgroundColor = [NSColor blackColor].CGColor;

	_player = [[AVQueuePlayer alloc] init];

	_playerLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
	[_playerLayer setFrame:[_videoView bounds]];
	[_playerLayer setAutoresizingMask:kCALayerWidthSizable | kCALayerHeightSizable];
	[_playerLayer setBackgroundColor:[NSColor blackColor].CGColor];

	[_previewView.layer addSublayer:_playerLayer];
	
	//[_player addObserver:self forKeyPath:@"status" options:0 context:NULL];

	//[self playMovieFile];

	_livePlayer = [LivePlayer playerWithCALayer:_playerLayer];
}

- (void)playMovieFile{
	NSError *error;
	
	NSURL *url = [NSURL fileURLWithPath:@"/Users/ideawu/htdocs/tmp/a03.mov"];
	AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
	AVAssetReader *asset_reader = [[AVAssetReader alloc]initWithAsset:asset error:&error];
	AVAssetTrack* video_track = [[asset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
	
	NSMutableDictionary *dictionary = [[NSMutableDictionary alloc]init];
	[dictionary setObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
				   forKey:(NSString *)kCVPixelBufferPixelFormatTypeKey];
	AVAssetReaderTrackOutput *asset_reader_output = [[AVAssetReaderTrackOutput alloc] initWithTrack:video_track
																				   outputSettings:dictionary];
	
	if([asset_reader canAddOutput:asset_reader_output]){
		[asset_reader addOutput:asset_reader_output];
	}
	
	if(![asset_reader startReading]){
		return;
	};
	
	//NSTimeInterval frameDuration = 1.0 / video_track.nominalFrameRate;
	NSUInteger totalFrames = (CMTimeGetSeconds(asset.duration) + 1) * video_track.nominalFrameRate;
	NSMutableArray *frames = [[NSMutableArray alloc] initWithCapacity:totalFrames];
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
		while ([asset_reader status]==AVAssetReaderStatusReading) {
			CMSampleBufferRef buffer = [asset_reader_output copyNextSampleBuffer];
			if(!buffer){
				continue;
			}
		
			CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(buffer);
			CVPixelBufferLockBaseAddress(imageBuffer,0);
			uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
			size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
			size_t width = CVPixelBufferGetWidth(imageBuffer);
			size_t height = CVPixelBufferGetHeight(imageBuffer);
			
			CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
			CGContextRef newContext = CGBitmapContextCreate(baseAddress,
															width, height,
															8,
															bytesPerRow,
															colorSpace,
															kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
			CGImageRef newImage = CGBitmapContextCreateImage(newContext);
			CGContextRelease(newContext);
			CGColorSpaceRelease(colorSpace);
			
			//[_playerLayer performSelectorOnMainThread:@selector(setContents:) withObject:(__bridge id)newImage waitUntilDone:YES];
			[frames addObject:(__bridge id)newImage];
			
			CFRelease(newImage);
			CFRelease(buffer);
			
			//[NSThread sleepForTimeInterval:frameDuration];
		}
		NSLog(@"total frames: %d, frames: %d", (int)totalFrames, (int)frames.count);
		
		dispatch_async(dispatch_get_main_queue(), ^{
			//return;
			CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"contents"];
			animation.duration = CMTimeGetSeconds(asset.duration);
			animation.values = frames;
			//animation.repeatCount = MAXFLOAT;
			animation.delegate = self;
			[_playerLayer addAnimation:animation forKey:nil];
		});
		
	});
}

- (void)animationDidStart:(CAAnimation *)anim{
	NSLog(@"%s", __func__);
}

- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag{
	NSLog(@"%s", __func__);
}


- (void)windowWillClose:(NSNotification *)notification{
	_playing = NO;
	[_player removeAllItems];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
						change:(NSDictionary *)change context:(void *)context {
	NSLog(@"%s %d", __func__, (int)_player.status);
	if(_player.status == AVPlayerStatusReadyToPlay){
		NSLog(@"play");
		[_player play];
	}
	return;
}

- (void)checkfile{
	NSLog(@"%s", __func__);
	NSString *tmpName = [NSString stringWithFormat:@"/Users/ideawu/Downloads/tmp/a%02d.mov", num];
	if(![[NSFileManager defaultManager] fileExistsAtPath:tmpName]){
		return;
	}
	if(_lastItem){
		if([_player canInsertItem:_lastItem afterItem:nil]){
			NSLog(@"add item %02d", num);
			[_player insertItem:_lastItem afterItem:nil];
		}else{
			NSLog(@"cannot add item: %02d", num);
		}
	}
	num ++;
	_lastItem = nil;
	NSURL *url = [NSURL fileURLWithPath:tmpName];
	_lastItem = [AVPlayerItem playerItemWithURL:url];

	if(_player.status == AVPlayerStatusReadyToPlay){
		NSLog(@"play");
		[_player play];
	}
}

- (void)streaming{
	if(!_downloadList){
		_downloadList = [[NSMutableArray alloc] init];
	}
	if(!_historyList){
		_historyList = [[NSMutableArray alloc] init];
	}
	if(!_downloadQueue){
		_downloadQueue = dispatch_queue_create("download queue", DISPATCH_QUEUE_SERIAL);
	}
	[self refreshPlaylist];
}

#define PLAYLIST_REFRESH_INTERVAL  2.0

- (void)refreshPlaylist{
	NSLog(@"%s", __func__);
	if(!_playing){
		return;
	}
	NSDate* startTime = [NSDate date];
	
	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
	[request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
	[request setTimeoutInterval:PLAYLIST_REFRESH_INTERVAL];
	[request setHTTPMethod:@"GET"];
	
	NSURL *req_url = [NSURL URLWithString:@"http://localhost/vbc/playlist.php"];
	[request setURL:req_url];
	
	[NSURLConnection sendAsynchronousRequest:request
									   queue:[[NSOperationQueue alloc] init]
						   completionHandler:^(NSURLResponse *urlresp, NSData *data, NSError *error)
	{
		NSHTTPURLResponse *response = (NSHTTPURLResponse *)urlresp;
		if(error || response.statusCode != 200){
			NSLog(@"HTTP error: %d, %@", (int)response.statusCode, (error? error.localizedDescription:@""));
			return;
		}
		//NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		//NSLog(@"resp: %@", str);
		
		double deltaTime = [[NSDate date] timeIntervalSinceDate:startTime];
		double sleepTime = PLAYLIST_REFRESH_INTERVAL - deltaTime;
		if(sleepTime <= 0 && sleepTime > PLAYLIST_REFRESH_INTERVAL){
			sleepTime = PLAYLIST_REFRESH_INTERVAL;
		}
		//NSLog(@"sleep %f", sleepTime);
		dispatch_async(_downloadQueue, ^{
			NSError *err = nil;
			id obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&err];
			if(!err && [obj isKindOfClass:[NSArray class]]){
				NSArray *arr = (NSArray *)obj;
				for(NSString *url in arr){
					if(![_downloadList containsObject:url] && ![_historyList containsObject:url]){
						NSLog(@"pending url: %@", url);
						[_downloadList addObject:url];
					}
				}
				if(_downloadList.count > 0){
					NSLog(@"www");
					[self downloadVideo];
				}
			}
		});
		
		dispatch_async(dispatch_get_main_queue(), ^{
			[NSTimer scheduledTimerWithTimeInterval:sleepTime target:self selector:@selector(refreshPlaylist) userInfo:nil repeats:NO];
		});
	 }];
}

- (void)downloadVideo{
	NSLog(@"%s", __func__);
	NSString *url = _downloadList.firstObject;
	if(!url){
		return;
	}
	[_downloadList removeObjectAtIndex:0];
	[_historyList addObject:url];
	if(_historyList.count > 20){
		[_historyList removeObjectAtIndex:0];
	}
	
	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
	[request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
	[request setTimeoutInterval:3];
	[request setHTTPMethod:@"GET"];
	
	NSURL *req_url = [NSURL URLWithString:url];
	[request setURL:req_url];
	
	[NSURLConnection sendAsynchronousRequest:request
									   queue:[[NSOperationQueue alloc] init]
						   completionHandler:^(NSURLResponse *urlresp, NSData *data, NSError *error)
	{
		NSHTTPURLResponse *response = (NSHTTPURLResponse *)urlresp;
		if(error || response.statusCode != 200){
			NSLog(@"HTTP error: %d, %@", (int)response.statusCode, (error? error.localizedDescription:@""));
			return;
		}
		
		dispatch_async(_downloadQueue, ^{
			[_livePlayer addMovieData:data originalPath:url];
			[self downloadVideo];
		});
	}];
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
	AVPlayerItem *item = (AVPlayerItem *)notification.object;
	AVURLAsset *asset = (AVURLAsset *)item.asset;
	NSLog(@"item play end: %@", asset.URL.absoluteString);
	//dispatch_async(_downloadQueue, ^{
	//	[[NSFileManager defaultManager] removeItemAtURL:asset.URL error:nil];
	//});
}

- (IBAction)onPlay:(id)sender {
	NSLog(@"%s", __func__);
	_playing = YES;
	[self streaming]; return;
	
	//[_livePlayer play];

	
	/*
	NSString *tmpName = @"http://localhost/tmp/bipbop.m3u8";
	NSURL *url = [NSURL URLWithString:tmpName];
	_lastItem = [AVPlayerItem playerItemWithURL:url];
	[_player insertItem:_lastItem afterItem:nil];
	*/
	
	//[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkfile) userInfo:nil repeats:YES];
}

- (IBAction)onNextFrame:(id)sender {
//	[_livePlayer nextFrame];
}

- (IBAction)onLoad:(id)sender {
	[_livePlayer removeAllItems];
#if 0
	[_livePlayer addMovieFile:@"/Users/ideawu/htdocs/tmp/fileSequence0.ts"];
	[_livePlayer addMovieFile:@"/Users/ideawu/htdocs/tmp/fileSequence1.ts"];
	[_livePlayer addMovieFile:@"/Users/ideawu/htdocs/tmp/fileSequence3.ts"];
#else
	[_livePlayer addMovieFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"m004.mp4"]];
#endif
}

- (IBAction)onNextSkip:(id)sender {
	for(int i=0; i<10; i++){
//		[_livePlayer nextFrame];
	}
}

- (IBAction)prevFrame:(id)sender {
//	[_livePlayer prevFrame];
}

- (IBAction)onPrevSkip:(id)sender {
	for(int i=0; i<10; i++){
//		[_livePlayer prevFrame];
	}
}

@end
