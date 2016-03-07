//
//  AVEncoder.m
//  VideoTest
//
//  Created by ideawu on 12/18/15.
//  Copyright © 2015 ideawu. All rights reserved.
//

#import "LiveClipWriter.h"

@interface LiveClipWriter()
@property (nonatomic) NSString *filename;
@property (nonatomic) int width;
@property (nonatomic) int height;
@property (nonatomic) int bitrate;
@property (nonatomic) int audioSampleRate;
@property (nonatomic) AVAssetWriter *writer;
@property (nonatomic) AVAssetWriterInput *audioInput;
@property (nonatomic) AVAssetWriterInput *videoInput;
@property (nonatomic) double audioStartTime;
@property (nonatomic) double audioEndTime;
@property (nonatomic) double startTime;
@property (nonatomic) double endTime;
@end

@implementation LiveClipWriter

- (id)init{
	self = [super init];
	_width = 360;
	_height = 480;
	_bitrate = 1024 * 200;
	_audioSampleRate = 44100;
	return self;
}

- (id)initWithFilename:(NSString *)filename videoWidth:(int)width videoHeight:(int)height{
	self = [self init];
	_width = width;
	_height = height;
	_filename = filename;
	[self setup];
	return self;
}

- (void)setup{
	if([[NSFileManager defaultManager] fileExistsAtPath:_filename]){
		[[NSFileManager defaultManager] removeItemAtPath:_filename error:nil];
	}
	NSURL *url = [NSURL fileURLWithPath:_filename];
	_writer = [AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeMPEG4 error:nil];
	_writer.metadata = [self getMetadataItems];
	NSDictionary* settings;
	settings = @{
				 AVVideoCodecKey: AVVideoCodecH264,
				 AVVideoWidthKey: @(_width),
				 AVVideoHeightKey: @(_height),
				 AVVideoCompressionPropertiesKey: @{
						 AVVideoAverageBitRateKey: [NSNumber numberWithInt:_bitrate],
						 //AVVideoAllowFrameReorderingKey: @YES,
						 //AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
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
	_videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:settings];
	_videoInput.expectsMediaDataInRealTime = YES;
	[_writer addInput:_videoInput];

	AudioChannelLayout acl;
	bzero(&acl, sizeof(acl));
	acl.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
	settings = @{
				 AVFormatIDKey : @(kAudioFormatMPEG4AAC),
				 AVSampleRateKey: @(_audioSampleRate),
				 //AVNumberOfChannelsKey: @(2),
				 AVChannelLayoutKey: [NSData dataWithBytes:&acl length:sizeof(acl)],
				 };
	_audioInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio outputSettings:settings];
	_audioInput.expectsMediaDataInRealTime = YES;
	[_writer addInput:_audioInput];
	
	if(![_writer startWriting]){
		NSLog(@"start writer failed: %@", _writer.error.description);
	}
}

- (void)encodeAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	[self encodeSampleBuffer:sampleBuffer ofMediaType:AVMediaTypeAudio];
}

- (void)encodeVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	[self encodeSampleBuffer:sampleBuffer ofMediaType:AVMediaTypeVideo];
}

- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer ofMediaType:(NSString *)mediaType{
	if (!CMSampleBufferDataIsReady(sampleBuffer)){
		NSLog(@"!CMSampleBufferDataIsReady");
		return;
	}
	
	double time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
	AVAssetWriterInput *input = (mediaType == AVMediaTypeVideo)? _videoInput : _audioInput;
	
	if(_startTime == 0 && _audioStartTime == 0){
		NSLog(@"start %@", _writer.outputURL.lastPathComponent);
		[_writer startSessionAtSourceTime:CMTimeMakeWithSeconds(time, 1)];
	}
	if (_writer.status == AVAssetWriterStatusFailed){
		//NSLog(@"writer error %@", _writer.error.localizedDescription);
		// TODO: set status
	}else if(input.readyForMoreMediaData == YES){
		int count = (int)CMSampleBufferGetNumSamples(sampleBuffer);
		if(mediaType == AVMediaTypeVideo){
			_frameCount += count;
		}else{
			_audioFrameCount += count;
		}
		[input appendSampleBuffer:sampleBuffer];
	}else{
		NSLog(@"!readyForMoreMediaData %d", (int)_writer.status);
	}
	
	double frameDuration = CMTimeGetSeconds(CMSampleBufferGetDuration(sampleBuffer));
	if(mediaType == AVMediaTypeVideo){
		if(_startTime == 0){
			_startTime = time;
		}
		_endTime = time;
		_endTime += frameDuration;
	}else{
		if(_audioStartTime == 0){
			_audioStartTime = time;
		}
		_audioEndTime = time;
		_audioEndTime += frameDuration;
	}
	
	_duration = _endTime - _startTime;
}

- (NSArray *)getMetadataItems{
	NSMutableArray * myMetadata = [NSMutableArray new];
	AVMutableMetadataItem * metadataItem;
	metadataItem = [AVMutableMetadataItem metadataItem];
	metadataItem.keySpace = AVMetadataKeySpaceCommon;
	metadataItem.key = AVMetadataCommonKeyDescription;
	// 先写入开始时间, 而结束时间留空, 最后再修改文件, 写入结束时间
	metadataItem.value = [self metastr];
	[myMetadata addObject: metadataItem];
	return myMetadata;
}

- (void)writeMetadata{
	NSLog(@"writting endTime %@", _writer.outputURL.lastPathComponent);
	NSFileHandle *file = [NSFileHandle fileHandleForUpdatingAtPath:_writer.outputURL.path];
	[file seekToEndOfFile];
	uint64_t file_len = [file offsetInFile];
	NSData *metadata = [[self metastr] dataUsingEncoding:NSUTF8StringEncoding];
	NSUInteger pos = file_len - metadata.length - 1; // +\0;
	[file seekToFileOffset:pos];
	[file writeData:metadata];
	[file closeFile];
}

+ (NSString *)metadataFormat{
	// %20.5f 只占用 20 宽度
	return @"TIMEINFO,%20.5f,%20.5f,%20d,%20.5f,%20.5f,%20d";
}

- (NSString *)metastr{
	return [NSString stringWithFormat:[LiveClipWriter metadataFormat],
					 _startTime, _endTime, _frameCount, _audioStartTime, _audioEndTime, _audioFrameCount];
}

- (void)updateMetadata:(NSMutableData *)data{
	NSData *metadata = [[self metastr] dataUsingEncoding:NSUTF8StringEncoding];
	NSUInteger pos = data.length - metadata.length - 1; // +\0;
	NSRange range = NSMakeRange(pos, metadata.length);
	[data replaceBytesInRange:range withBytes:metadata.bytes length:metadata.length];
#ifdef DEBUG
	[self writeMetadata];
#endif
}

- (void)finishWritingWithCompletionHandler:(void (^)(NSData *))handler{
	[_writer finishWritingWithCompletionHandler:^{
		if(_writer.status != AVAssetWriterStatusCompleted){
			NSLog(@"asset writer failed: %@", _writer.outputURL.lastPathComponent);
			return;
		}

		NSMutableData *data = [[NSMutableData alloc] initWithContentsOfURL:_writer.outputURL];
		if(!data){
			NSLog(@"nil data");
			return;
		}
		[self updateMetadata:data];

		NSLog(@"finish %@, %d byte(s)", _writer.outputURL.lastPathComponent, (int)data.length);
		if(handler){
			handler(data);
		}

		double fps = (_duration == 0.0)? 0 : _frameCount / _duration;
		NSLog(@"frames: %d, fps: %.3f, duration: %.4f, audioDuration: %.4f, audioSampleCount: %d",
			  _frameCount, fps, _duration, _audioEndTime - _audioStartTime, _audioFrameCount);
	}];
}

@end
