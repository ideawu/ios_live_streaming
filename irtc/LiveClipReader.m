//
//  LiveClipReader.m
//  VideoTest
//
//  Created by ideawu on 12/20/15.
//  Copyright © 2015 ideawu. All rights reserved.
//

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif
#import "LiveClipReader.h"

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
	
	AVAssetTrack* audio_track;


	int _nextIndex;
	int _approximatedFrameCount;
	double _sessionStartTime;
}
@property (nonatomic, readonly) LiveClipReaderStatus status;
@property (nonatomic, readonly) NSURL *URL;
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
	
	audio_track = [_asset tracksWithMediaType:AVMediaTypeAudio].lastObject;
	if(audio_track){
		settings = @{
					 AVFormatIDKey: @(kAudioFormatLinearPCM),
					 };
		_audioOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:audio_track
														outputSettings:settings];
		if([_assetReader canAddOutput:_audioOutput]){
			[_assetReader addOutput:_audioOutput];
		}
	}

	AVAssetTrack* video_track = [_asset tracksWithMediaType:AVMediaTypeVideo].lastObject;
	if(video_track){
		settings = @{
					 (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
					 };
		_videoOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:video_track
														outputSettings:settings];
		_videoOutput.alwaysCopiesSampleData = NO;
		if([_assetReader canAddOutput:_videoOutput]){
			[_assetReader addOutput:_videoOutput];
		}
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
	[self readAudioInfo];
	
	return self;
}

- (void)readAudioInfo{
	AudioFileID fileID  = nil;
	OSStatus err=noErr;
	err = AudioFileOpenURL( (__bridge CFURLRef) _URL, kAudioFileReadPermission, 0, &fileID );
	if( err != noErr ) {
		NSLog( @"AudioFileOpenURL failed" );
	}
	
	UInt32 size = sizeof(_audioInfo);
	AudioFileGetProperty(fileID, kAudioFilePropertyPacketTableInfo, &size, &_audioInfo);
	//NSLog(@"priming: %d remainder: %d total: %d", _audioInfo.mPrimingFrames, _audioInfo.mRemainderFrames, (int)_audioInfo.mNumberValidFrames);
	
	AudioFileClose(fileID);
	
	NSArray* descs = audio_track.formatDescriptions;
	for(unsigned int i = 0; i < [descs count]; ++i) {
		CMAudioFormatDescriptionRef item = (__bridge CMAudioFormatDescriptionRef)[descs objectAtIndex:i];
		const AudioStreamBasicDescription* fmtDesc = CMAudioFormatDescriptionGetStreamBasicDescription(item);
		if(fmtDesc){
			_audioFormat = *fmtDesc;
			_audioFormat.mFormatID = kAudioFormatLinearPCM;
			break;
		}
	}

	NSMutableData *data = [[NSMutableData alloc] init];
	while(1){
		CMSampleBufferRef sampleBuffer = [_audioOutput copyNextSampleBuffer];
		if(!sampleBuffer){
			break;
		}
		
		if(_audioFormat.mBytesPerFrame == 0){
			_audioFormat = *CMAudioFormatDescriptionGetStreamBasicDescription((CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer));
//			NSLog(@"format.mSampleRate:       %f", _audioFormat.mSampleRate);
//			NSLog(@"format.mBitsPerChannel:   %d", _audioFormat.mBitsPerChannel); //
//			NSLog(@"format.mChannelsPerFrame: %d", _audioFormat.mChannelsPerFrame);
//			NSLog(@"format.mBytesPerFrame:    %d", _audioFormat.mBytesPerFrame); //
//			NSLog(@"format.mFramesPerPacket:  %d", _audioFormat.mFramesPerPacket);
//			NSLog(@"format.mBytesPerPacket:   %d", _audioFormat.mBytesPerPacket); //
		}
		
		CMBlockBufferRef blockBuffer;
		AudioBufferList audioBufferList;
		
		OSStatus err;
		err = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
																	  sampleBuffer,
																	  NULL,
																	  &audioBufferList,
																	  sizeof(AudioBufferList),
																	  NULL,
																	  NULL,
																	  kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
																	  &blockBuffer
																	  );
		if(err){
			NSLog(@"%d error", __LINE__);
		}
		
		for (NSUInteger i = 0; i < audioBufferList.mNumberBuffers; i++) {
			AudioBuffer audioBuffer = audioBufferList.mBuffers[i];
			[data appendBytes:audioBuffer.mData length:audioBuffer.mDataByteSize];
		}
		
		CFRelease(blockBuffer);
		CFRelease(sampleBuffer);
	}
	
	// trim priming/remainder
	NSUInteger priming = _audioInfo.mPrimingFrames * _audioFormat.mBytesPerFrame;
	NSUInteger remainder = _audioInfo.mRemainderFrames * _audioFormat.mBytesPerFrame;
	NSUInteger data_len = data.length - priming - remainder;
	NSUInteger real_data_len = _audioFrameCount * _audioFormat.mBytesPerFrame;
	if(real_data_len < data_len){
		remainder += data_len - real_data_len;
	}
	NSRange range;
	if(remainder > 0){
		 range = NSMakeRange(data.length - remainder - 1, remainder);
		[data replaceBytesInRange:range withBytes:NULL length:0];
	}
	if(priming > 0){
		range = NSMakeRange(0, priming);
		[data replaceBytesInRange:range withBytes:NULL length:0];
	}
	_audioData = data;
}

- (void)readMetadata{
	int num_records = 6;
	// read metadata
	NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:_URL.path];
	[file seekToEndOfFile];
	uint64_t pos = [file offsetInFile];
	pos -= @"TIMEINFO,".length + 21 * num_records;
	[file seekToFileOffset:pos];
	NSData *data = [file readDataToEndOfFile];
	[file closeFile];
	NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if(!str){
		NSLog(@"empty metadata");
		return;
	}
	if([str rangeOfString:@"TIMEINFO,"].location != 0){
		NSLog(@"metadata not found");
		return;
	}
	NSArray *ps = [str componentsSeparatedByString:@","];
	if(ps.count != num_records + 1){
		NSLog(@"bad metadata: %@", ps);
		return;
	}
	
	_startTime = [ps[1] doubleValue];
	_endTime = [ps[2] doubleValue];
	_frameCount = [ps[3] intValue];
	_duration = _endTime - _startTime;
	_frameDuration = _duration / _frameCount;
	double fps = (_duration == 0.0)? 0 : _frameCount / _duration;
	_audioDuration = [ps[5] doubleValue] - [ps[4] doubleValue];
	_audioFrameCount = [ps[6] intValue];
	NSLog(@"fps: %.3f, frames: %d, duration: %.3f, audioDuration: %.3f, audioFrames: %d",
		  fps, _frameCount, _duration, _audioDuration, _audioFrameCount);
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
	// TODO:
	// 似乎 mp4 的第一帧是黑屏
	// drop first frame
	CGImageRef first = [self copyNextFrame];
	if(first){
		CFRelease(first);
	}
}

- (BOOL)hasNextFrameForTime:(double)time{
	double elapse = time - _sessionStartTime;
	if(elapse < 0){
		return NO;
	}
	if(elapse > _duration){
		return NO;
	}
	
	double maxAhead = -MIN(0.01, _frameDuration/10);
	double expect = _nextIndex * _frameDuration;
	double delay = elapse - expect;
	if(delay >= 0){
		return YES;
	}else if(delay >= maxAhead){
		return YES;
	}
	return NO;
}

- (CGImageRef)copyNextFrameForTime:(double)time{
	if(_sessionStartTime == 0){
		_sessionStartTime = time;
		_status = LiveClipReaderStatusReading;
	}
	if(!self.isReading){
		return nil;
	}
	double elapse = time - _sessionStartTime;
	// 如果时间已经过, 或者太超前, 都结束
	if(elapse > _duration || elapse < -3){
		NSLog(@"complete %d of %d frames", _nextIndex, _frameCount);
		_status = LiveClipReaderStatusCompleted;
		return nil;
	}
	if(![self hasNextFrameForTime:time]){
		return nil;
	}

	CGImageRef image = [self copyNextFrame];
	if(_assetReader.status == AVAssetReaderStatusFailed){
		_status = LiveClipReaderStatusCompleted;
	}else if(_assetReader.status == AVAssetReaderStatusCancelled){
		_status = LiveClipReaderStatusCompleted;
	}else if(_assetReader.status == AVAssetReaderStatusCompleted){
		_status = LiveClipReaderStatusCompleted;
	}
	
	_delay = elapse - _nextIndex * _frameDuration;
	if(_delay > _frameDuration){
		NSLog(@"frame: %d/%d, delay: %.3f, now: %.3f, end: %.3f", _nextIndex+1, _frameCount, _delay, time, _endTime);
	}
	_nextIndex ++;
	return image;
}

- (CGImageRef)copyNextFrame{
	CMSampleBufferRef buffer = [_videoOutput copyNextSampleBuffer];
	if(!buffer){
		//NSLog(@"nil buffer");
		return nil;
	}
	// CVImageBufferRef 即是 CVPixelBufferRef
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
	//CFRelease(buffer); // 由调用者负责释放
	return image;
}

@end
