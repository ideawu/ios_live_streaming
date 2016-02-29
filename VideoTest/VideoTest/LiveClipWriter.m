//
//  AVEncoder.m
//  VideoTest
//
//  Created by ideawu on 12/18/15.
//  Copyright © 2015 ideawu. All rights reserved.
//

#import "LiveClipWriter.h"

@interface LiveClipWriter()
@property (nonatomic) int width;
@property (nonatomic) int height;
@property (nonatomic) AVAssetWriterInput *audioInput;
@property (nonatomic) AVAssetWriterInput *videoInput;
@end

@implementation LiveClipWriter

- (id)init{
	self = [super init];
	_width = 320;
	_height = 240;
	return self;
}

- (id)initWithFilename:(NSString *)filename{
	self = [self init];
	
	if([[NSFileManager defaultManager] fileExistsAtPath:filename]){
		[[NSFileManager defaultManager] removeItemAtPath:filename error:nil];
	}
	NSURL *url = [NSURL fileURLWithPath:filename];
	_writer = [AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeMPEG4 error:nil];
	int bitrate = 1024 * 200;
	NSDictionary* settings = @{
							AVVideoCodecKey: AVVideoCodecH264,
							AVVideoWidthKey: @(_width),
							AVVideoHeightKey: @(_height),
							AVVideoCompressionPropertiesKey: @{
									AVVideoAverageBitRateKey: [NSNumber numberWithInt:bitrate],
//									AVVideoAllowFrameReorderingKey: @NO,
//									AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
									},
							// belows require OS X 10.10+
							//AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCAVLC,
							//AVVideoExpectedSourceFrameRateKey: @(30),
							//AVVideoAllowFrameReorderingKey: @NO,
							};
#if TARGET_OS_MAC
#ifdef NSFoundationVersionNumber10_9_2
	if(NSFoundationVersionNumber <= NSFoundationVersionNumber10_9_2){
		NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:settings];
		// AVVideoCodecH264 not working right with OS X 10.9-
		[dict setObject:AVVideoCodecJPEG forKey:AVVideoCodecKey];
		settings = dict;
	}
#endif
#endif
	_videoInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:settings];
	_videoInput.expectsMediaDataInRealTime = YES;
	[_writer addInput:_videoInput];
	
	
//	audioOutputSettings = [NSDictionary dictionaryWithObjectsAndKeys:
//						   [ NSNumber numberWithInt: kAudioFormatMPEG4AAC ], AVFormatIDKey,
//						   [ NSNumber numberWithInt: 2 ], AVNumberOfChannelsKey,
//						   [ NSNumber numberWithFloat: 44100.0 ], AVSampleRateKey,
//						   [ NSNumber numberWithInt: 64000 ], AVEncoderBitRateKey,
//						   [ NSData dataWithBytes: &acl length: sizeof( acl ) ], AVChannelLayoutKey,
//						   nil];

	AudioChannelLayout acl;
	bzero(&acl, sizeof(acl));
	acl.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
	settings = @{
				 AVFormatIDKey : @(kAudioFormatMPEG4AAC),
				 AVSampleRateKey: @(44100.0),
				 AVChannelLayoutKey: [NSData dataWithBytes:&acl length:sizeof(acl)],
				 };
	_audioInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio outputSettings:settings];
	_audioInput.expectsMediaDataInRealTime = YES;
	[_writer addInput:_audioInput];

	return self;
}

- (void)encodeAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer ofMediaType:(NSString *)mediaType{
	if (!CMSampleBufferDataIsReady(sampleBuffer)){
		NSLog(@"!CMSampleBufferDataIsReady");
		return;
	}
	
	AVAssetWriterInput *input = (mediaType == AVMediaTypeVideo)? _videoInput : _audioInput;
	
	if (_writer.status == AVAssetWriterStatusUnknown){
		_startTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
		NSLog(@"start %@", _writer.outputURL.lastPathComponent);
		_writer.metadata = [self getMetadataItems];
		[_writer startWriting];
		[_writer startSessionAtSourceTime:CMTimeMakeWithSeconds(_startTime, 1)];
	}
	if (_writer.status == AVAssetWriterStatusFailed){
		NSLog(@"writer error %@", _writer.error.localizedDescription);
	}else if(input.readyForMoreMediaData == YES){
		if(mediaType == AVMediaTypeVideo){
			_frameCount ++;
		}
		[input appendSampleBuffer:sampleBuffer];
	}else{
		NSLog(@"!readyForMoreMediaData");
	}
	
	_endTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
	_duration = _endTime - _startTime;
}

- (void)encodeAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	[self encodeAudioSampleBuffer:sampleBuffer ofMediaType:AVMediaTypeAudio];
}


- (void)encodeVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	[self encodeAudioSampleBuffer:sampleBuffer ofMediaType:AVMediaTypeVideo];
}

- (NSArray *)getMetadataItems{
	NSMutableArray * myMetadata = [NSMutableArray new];
	AVMutableMetadataItem * metadataItem;
	metadataItem = [AVMutableMetadataItem metadataItem];
	metadataItem.keySpace = AVMetadataKeySpaceCommon;
	metadataItem.key = AVMetadataCommonKeyDescription;
	// 先写入开始时间, 而结束时间留空, 最后再修改文件, 写入结束时间
	metadataItem.value = [NSString stringWithFormat:@"TIMEINFO,%20.5f,%20.5f,%10d", _startTime, 0.0, 0];
	[myMetadata addObject: metadataItem];
	return myMetadata;
}

- (void)writeMetadata{
	NSLog(@"writting endTime %@", _writer.outputURL.lastPathComponent);
	NSFileHandle *file = [NSFileHandle fileHandleForUpdatingAtPath:_writer.outputURL.path];
	[file seekToEndOfFile];
	uint64_t pos = [file offsetInFile];
	pos -= (20 + 1 + 10) + 1; // +\0
	[file seekToFileOffset:pos];
	NSString *str = [NSString stringWithFormat:@"%20.5f,%10d", _endTime, _frameCount];
	NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
	[file writeData:data];
	[file closeFile];
}

- (void)finishWritingWithCompletionHandler:(void (^)())handler{
	[_writer finishWritingWithCompletionHandler:^{
		[self writeMetadata];

		NSLog(@"stopped %@", _writer.outputURL.lastPathComponent);
		if(handler){
			handler();
		}

		double fps = (_duration == 0.0)? 0 : _frameCount / _duration;
		NSLog(@"stime: %f, etime: %f, frames: %d, duration: %f, fps: %f", _startTime, _endTime, _frameCount, _duration, fps);
	}];
}

@end
