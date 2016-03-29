//
//  MovieCaptureFile.m
//  irtc
//
//  Created by ideawu on 3/15/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "MovieCaptureFile.h"
#import "LiveCapture.h"

@interface MovieCaptureFile(){
	LiveCapture *_capture;
}
@property (nonatomic) AVAssetWriter *writer;
@property (nonatomic) AVAssetWriterInput *audioInput;
@property (nonatomic) AVAssetWriterInput *videoInput;
@end


@implementation MovieCaptureFile

- (id)init{
	self = [super init];
	_width = 640;
	_height = 480;
	_audioSampleRate = 44100;
	return self;
}

- (void)start{
	[self setupWriter];
	__weak typeof(self) me = self;
	
	_capture = [[LiveCapture alloc] init];
	[_capture setupVideo:^(CMSampleBufferRef sampleBuffer) {
		[me onVideoCapturedSampleBuffer:sampleBuffer];
	}];
	[_capture start];
}

- (void)stop{
	[_capture stop];
	
	[_writer finishWritingWithCompletionHandler:^{
		if(_writer.status != AVAssetWriterStatusCompleted){
			log_debug(@"asset writer failed: %@", _writer.outputURL.lastPathComponent);
			return;
		}
		log_debug(@"writed to %@", _filename);
	}];
}

- (void)setupWriter{
	if([[NSFileManager defaultManager] fileExistsAtPath:_filename]){
		[[NSFileManager defaultManager] removeItemAtPath:_filename error:nil];
	}
	NSURL *url = [NSURL fileURLWithPath:_filename];
	_writer = [AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeMPEG4 error:nil];
	NSDictionary* settings;
	settings = @{
				 AVVideoCodecKey: AVVideoCodecH264,
				 AVVideoWidthKey: @(_width),
				 AVVideoHeightKey: @(_height),
				 AVVideoCompressionPropertiesKey: @{
						 //AVVideoAverageBitRateKey: [NSNumber numberWithInt:_bitrate],
						 //AVVideoAllowFrameReorderingKey: @YES,
						 //AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
						 },
				 // belows require OS X 10.10+
				 //AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCAVLC,
				 //AVVideoExpectedSourceFrameRateKey: @(30),
				 //AVVideoAllowFrameReorderingKey: @NO,
				 };
#if !TARGET_OS_IPHONE
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
}

- (void)onVideoCapturedSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	double time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));

	CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
	log_debug(@"width: %d, height: %d, %d bytes",
			  (int)CVPixelBufferGetWidth(imageBuffer),
			  (int)CVPixelBufferGetHeight(imageBuffer),
			  (int)CVPixelBufferGetDataSize(imageBuffer)
			  );

	if (_writer.status == AVAssetWriterStatusUnknown){
		log_debug(@"start %@", _writer.outputURL.lastPathComponent);
		if(![_writer startWriting]){
			log_debug(@"start writer failed: %@", _writer.error.description);
		}
		[_writer startSessionAtSourceTime:CMTimeMakeWithSeconds(time, 1)];
	}
	if (_writer.status == AVAssetWriterStatusFailed){
		log_debug(@"writer error %@", _writer.error.localizedDescription);
		// TODO: set status
	}else if(_videoInput.readyForMoreMediaData == YES){
		[_videoInput appendSampleBuffer:sampleBuffer];
	}else{
		log_debug(@"!readyForMoreMediaData %d", (int)_writer.status);
	}
}

@end
