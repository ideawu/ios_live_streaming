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
@property (nonatomic) int bitrate;
@property (nonatomic) AVAssetWriterInput *videoInput;
@end

@implementation LiveClipWriter

- (id)init{
	self = [super init];
	_width = 360;
	_height = 480;
	_bitrate = 1024 * 200;
	return self;
}

- (id)initWithFilename:(NSString *)filename videoWidth:(int)width videoHeight:(int)height{
	self = [self init];
	_width = width;
	_height = height;
	
	if([[NSFileManager defaultManager] fileExistsAtPath:filename]){
		[[NSFileManager defaultManager] removeItemAtPath:filename error:nil];
	}
	NSURL *url = [NSURL fileURLWithPath:filename];
	_writer = [AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeMPEG4 error:nil];
	NSDictionary* settings = @{
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

	return self;
}

- (void)encodeVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	if (!CMSampleBufferDataIsReady(sampleBuffer)){
		NSLog(@"!CMSampleBufferDataIsReady");
		return;
	}

	if (_writer.status == AVAssetWriterStatusUnknown){
		_startTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
		NSLog(@"start %@", _writer.outputURL.lastPathComponent);
		_writer.metadata = [self getMetadataItems];
		[_writer startWriting];
		[_writer startSessionAtSourceTime:CMTimeMakeWithSeconds(_startTime, 1)];
	}
	if (_writer.status == AVAssetWriterStatusFailed){
		NSLog(@"writer error %@", _writer.error.localizedDescription);
	}else if(_videoInput.readyForMoreMediaData == YES){
		_frameCount ++;
		[_videoInput appendSampleBuffer:sampleBuffer];
	}else{
		NSLog(@"!readyForMoreMediaData");
	}

	_endTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
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

//- (void)writeMetadata{
//	NSLog(@"writting endTime %@", _writer.outputURL.lastPathComponent);
//	NSFileHandle *file = [NSFileHandle fileHandleForUpdatingAtPath:_writer.outputURL.path];
//	[file seekToEndOfFile];
//	uint64_t pos = [file offsetInFile];
//	pos -= (20 + 1 + 10) + 1; // +\0
//	[file seekToFileOffset:pos];
//	NSString *str = [NSString stringWithFormat:@"%20.5f,%10d", _endTime, _frameCount];
//	NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
//	[file writeData:data];
//	[file closeFile];
//}

- (NSString *)metastr{
	return [NSString stringWithFormat:@"TIMEINFO,%20.5f,%20.5f,%10d",
					 _startTime, _endTime, _frameCount];
}

- (void)updateMetadata:(NSMutableData *)data{
	NSData *metadata = [[self metastr] dataUsingEncoding:NSUTF8StringEncoding];
	NSUInteger pos = data.length - metadata.length - 1; // +\0;
	NSRange range = NSMakeRange(pos, metadata.length);
	[data replaceBytesInRange:range withBytes:metadata.bytes length:metadata.length];
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
		NSLog(@"stime: %.3f, etime: %.3f, frames: %d, duration: %.3f, fps: %.3f",
			  _startTime, _endTime, _frameCount, _duration, fps);
	}];
}

@end
