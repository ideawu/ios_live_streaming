//
//  LiveClipReader.m
//  VideoTest
//
//  Created by ideawu on 12/20/15.
//  Copyright © 2015 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import "LiveClipReader.h"
#import "AudioPlayer.h"

typedef enum{
	LiveClipReaderStatusNone = 0,
	LiveClipReaderStatusReading,
	LiveClipReaderStatusCompleted,
}LiveClipReaderStatus;

@interface LiveClipReader(){
	AVURLAsset *_asset;
	AVAssetReader *_assetReader;
	AVAssetReaderTrackOutput *_audioOutput;
	AVAssetReaderTrackOutput *_videoOutput;
	int _nextIndex;
	int _approximatedFrameCount;
	double _sessionStartTime;
	
	AudioPlayer *_audio;
}
@property (nonatomic, readonly) LiveClipReaderStatus status;
@end

@implementation LiveClipReader

+ (LiveClipReader *)clipReaderWithURL:(NSURL *)url{
	LiveClipReader *item = [[LiveClipReader alloc] initWithURL:url];
	return item;
}

- (id)initWithURL:(NSURL *)url{
	self = [self init];
	_URL = url;
	
	NSError *error;
	_asset = [AVURLAsset URLAssetWithURL:url options:nil];
	_assetReader = [[AVAssetReader alloc] initWithAsset:_asset error:&error];
	if(error){
		NSLog(@"error: %@", error);
		return self;
	}
	
	NSDictionary *settings;
	
	AVAssetTrack* video_track = [_asset tracksWithMediaType:AVMediaTypeVideo].lastObject;
	settings = @{
			  (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
			  };
	_videoOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:video_track
													outputSettings:settings];
	_videoOutput.alwaysCopiesSampleData = NO;
	if([_assetReader canAddOutput:_videoOutput]){
		[_assetReader addOutput:_videoOutput];
	}
	
	AVAssetTrack* audio_track = [_asset tracksWithMediaType:AVMediaTypeAudio].lastObject;
	settings = @{
				 AVFormatIDKey: @(kAudioFormatLinearPCM),
				 };
	_audioOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:audio_track
														  outputSettings:settings];
	if([_assetReader canAddOutput:_audioOutput]){
		[_assetReader addOutput:_audioOutput];
	}

	
	
	if([_assetReader startReading]){
		NSLog(@"du: %f, fps: %f", CMTimeGetSeconds(video_track.timeRange.duration), video_track.nominalFrameRate);
		_frameDuration = 1.0/video_track.nominalFrameRate;
		_startTime = 0;
		_endTime = 86400*100;
		_duration = _endTime - _startTime;
		_nextIndex = 0;
		_approximatedFrameCount = (int)ceil(CMTimeGetSeconds(video_track.timeRange.duration) / _frameDuration);
	}

	[self test];

	[self readMetadata];

	return self;
}

- (void)test{
	_audio = [[AudioPlayer alloc] init];
	
	int n = 0;
	while(1){
		CMSampleBufferRef sampleBuffer = [_audioOutput copyNextSampleBuffer];
		if(!sampleBuffer){
			break;
		}
		n ++;
		
		[_audio appendSampleBuffer:sampleBuffer];
		
		CFRelease(sampleBuffer);
	}
	NSLog(@"audio samples = %d", n);
}

- (void)readMetadata{
	// read metadata
	NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:_URL.path];
	[file seekToEndOfFile];
	uint64_t pos = [file offsetInFile];
	pos -= @"TIMEINFO,".length + 20 + 1 + 20 + 1 + 10 + 1;
	[file seekToFileOffset:pos];
	NSData *data = [file readDataToEndOfFile];
	[file closeFile];
	NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	NSLog(@"%@", str);
	if([str rangeOfString:@"TIMEINFO,"].location != 0){
		NSLog(@"metadata not found");
		return;
	}
	NSArray *ps = [str componentsSeparatedByString:@","];
	if(ps.count != 4){
		NSLog(@"bad metadata");
		return;
	}
	_startTime = [ps[1] doubleValue];
	_endTime = [ps[2] doubleValue];
	_frameCount = [ps[3] intValue];
	_duration = _endTime - _startTime;
	_frameDuration = _duration / _frameCount;
	double fps = (_duration == 0.0)? 0 : _frameCount / _duration;
	NSLog(@"stime: %f, etime: %f, frames: %d, duration: %f, fps: %f", _startTime, _endTime, _frameCount, _duration, fps);
}

- (BOOL)isReading{
	return _status == LiveClipReaderStatusReading;
}

- (BOOL)isCompleted{
	return _status == LiveClipReaderStatusCompleted;
}

- (double)convertToHostTime:(double)time{
	return time - _sessionStartTime + _startTime;
}

- (void)startSessionAtSourceTime:(double)time{
	_sessionStartTime = time;
	_nextIndex = 0;
	_status = LiveClipReaderStatusReading;
}

- (BOOL)hasNextFrameForTime:(double)time{
	if(_startTime == 0 && _duration > 0){
		return YES;
	}
	if(time < _startTime || time > _endTime){
		return NO;
	}
	double mayDelay = time - (_startTime + _nextIndex * _frameDuration);
	if(mayDelay > MAX(-0.01, -_frameDuration/10)){
		return YES;
	}
	return NO;
}

- (CGImageRef)copyNextFrameForTime:(double)time{
	if(_sessionStartTime == 0){
		_sessionStartTime = time;
		_status = LiveClipReaderStatusReading;
	}
	time = [self convertToHostTime:time];
	if(!self.isReading){
		return nil;
	}
	if(time > _endTime){
		NSLog(@"complete");
		_status = LiveClipReaderStatusCompleted;
	}
	if(![self hasNextFrameForTime:time]){
		return nil;
	}
	
	CMSampleBufferRef buffer = [_videoOutput copyNextSampleBuffer];
	if(_assetReader.status == AVAssetReaderStatusFailed){
		_status = LiveClipReaderStatusCompleted;
	}else if(_assetReader.status == AVAssetReaderStatusCancelled){
		_status = LiveClipReaderStatusCompleted;
	}else if(_assetReader.status == AVAssetReaderStatusCompleted){
		_status = LiveClipReaderStatusCompleted;
	}
	if(!buffer){
		return nil;
	}
	_delay = time - (_startTime + _nextIndex * _frameDuration);
	
	CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(buffer);
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
	CGImageRef image = CGBitmapContextCreateImage(context);
	CGColorSpaceRelease(colorSpace);
	CGContextRelease(context);
	//CFRelease(buffer);

	NSLog(@"frame: %d/~%d, delay: %f", _nextIndex+1, _approximatedFrameCount, _delay);
	_nextIndex ++;
	return image;
}

@end
