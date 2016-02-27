//
//  LiveClipReader.m
//  VideoTest
//
//  Created by ideawu on 12/20/15.
//  Copyright © 2015 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import "LiveClipReader.h"

typedef enum{
	LiveClipReaderStatusNone = 0,
	LiveClipReaderStatusReading,
	LiveClipReaderStatusCompleted,
}LiveClipReaderStatus;

@interface LiveClipReader(){
	AVURLAsset *_asset;
	AVAssetReader *_assetReader;
	AVAssetReaderTrackOutput *_assetReaderOutput;
	int _nextIndex;
	int _approximatedFrameCount;
	double _sessionStartTime;
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
	AVAssetTrack* video_track = [_asset tracksWithMediaType:AVMediaTypeVideo].lastObject;
	
	NSMutableDictionary *dictionary = [[NSMutableDictionary alloc]init];
	[dictionary setObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
				   forKey:(NSString *)kCVPixelBufferPixelFormatTypeKey];
	_assetReaderOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:video_track
														  outputSettings:dictionary];
	
	if([_assetReader canAddOutput:_assetReaderOutput]){
		[_assetReader addOutput:_assetReaderOutput];
	}
	if([_assetReader startReading]){
		//NSLog(@"duration: %f, fps: %f", CMTimeGetSeconds(video_track.timeRange.duration), video_track.nominalFrameRate);
		_frameDuration = 1.0/video_track.nominalFrameRate;
		_startTime = 0;
		_endTime = 86400*100;
		_duration = _endTime - _startTime;
		_nextIndex = 0;
		_approximatedFrameCount = (int)ceil(CMTimeGetSeconds(video_track.timeRange.duration) / _frameDuration);
	}

	[self readMetadata];

	return self;
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
	if(!str){
		NSLog(@"empty metadata");
	}
	if([str rangeOfString:@"TIMEINFO,"].location != 0){
		NSLog(@"metadata not found");
		return;
	}
	NSArray *ps = [str componentsSeparatedByString:@","];
	if(ps.count != 4){
		NSLog(@"bad metadata: %@", ps);
		return;
	}
	
	_startTime = [ps[1] doubleValue];
	_endTime = [ps[2] doubleValue];
	_frameCount = [ps[3] intValue];
	_duration = _endTime - _startTime;
	_frameDuration = _duration / _frameCount;
	double fps = (_duration == 0.0)? 0 : _frameCount / _duration;
	NSLog(@"stime: %.3f, etime: %.3f, fps: %.3f, frames: %d, duration: %.3f", _startTime, _endTime, fps, _frameCount, _duration);
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
	if(time > _endTime || _nextIndex > _frameCount){
		NSLog(@"complete %d frames", _nextIndex);
		_status = LiveClipReaderStatusCompleted;
	}
	if(![self hasNextFrameForTime:time]){
		return nil;
	}
	
	CMSampleBufferRef buffer = [_assetReaderOutput copyNextSampleBuffer];
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

	//NSLog(@"frame: %d/%d, delay: %.3f, time: %.3f, endTime: %.3f", _nextIndex+1, _frameCount, _delay, time, _endTime);
	_nextIndex ++;
	return image;
}

@end
