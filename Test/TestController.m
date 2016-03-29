//
//  TestController.m
//  irtc
//
//  Created by ideawu on 16-3-5.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import "TestController.h"
#import <AVFoundation/AVFoundation.h>
#import "LiveRecorder.h"
#import "VideoPlayer.h"
#import "AudioPlayer.h"
#import "AudioDecoder.h"
#import "VideoDecoder.h"
#import "VideoEncoder.h"
#import "VideoReader.h"

@interface TestController (){
	CALayer *_videoLayer;
	LiveRecorder *_recorder;
	VideoPlayer *_player;
	AudioPlayer *_audioPlayer;
	AudioDecoder *_audioDecoder;

}
@property int num;
@end

@implementation TestController

- (void)windowDidLoad {
    [super windowDidLoad];

	_videoLayer = [[CALayer alloc] init];
	_videoLayer.frame = self.videoView.bounds;
	_videoLayer.bounds = self.videoView.bounds;

	[[self.videoView layer] addSublayer:_videoLayer];
	_videoView.layer.backgroundColor = [NSColor blackColor].CGColor;

	[self capture];
//	[self performSelectorInBackground:@selector(playFile) withObject:nil];
}

- (void)capture{
	//	__weak typeof(self) me = self;
	
	_recorder = [[LiveRecorder alloc] init];
	_recorder.clipDuration = 0.2;
	//_recorder.bitrate = 800 * 1024;
	
	_player = [[VideoPlayer alloc] init];
	_player.layer = _videoLayer;
	[_player play];
	
	[_recorder setupVideo:^(VideoClip *clip){
		NSData *data = clip.data;
		log_debug(@"%2d frames[%.3f ~ %.3f], duration: %.3f, %5d bytes, key_frame: %@",
			  clip.frameCount, clip.startTime, clip.endTime, clip.duration, (int)data.length,
			  clip.hasKeyFrame?@"yes":@"no");
		
		VideoClip *c = [[VideoClip alloc] init];
		[c parseData:data];
		[_player addClip:c];
	}];
	
	//	int raw_format = 1;
	//	if(raw_format){
	//		_audioPlayer = [[AudioPlayer alloc] init];
	//		[_audioPlayer setSampleRate:44100 channels:2];
	//	}else{
	//		_audioPlayer = [AudioPlayer AACPlayerWithSampleRate:44100 channels:2];
	//	}
	//
	//	_audioDecoder = [[AudioDecoder alloc] init];
	//	[_audioDecoder start:^(NSData *pcm, double duration) {
	//		[_audioPlayer appendData:pcm];
	//	}];
	//
	//	[_recorder setupAudio:^(NSData *data, double pts, double duration) {
	//		int i = [me incr];
	//		if(i > 130 && i < 350){
	//			//log_debug(@"return %d", i);
	//			return;
	//		}
	//		log_debug(@"%d bytes, %f %f", (int)data.length, pts, duration);
	//		if(raw_format){
	//			[_audioDecoder decode:data];
	//		}else{
	//			[_audioPlayer appendData:data];
	//		}
	//	}];
	
	[_recorder start];
}

- (void)playFile{
	VideoDecoder *_decoder = [[VideoDecoder alloc] init];
	[_decoder start:^(CVPixelBufferRef pixelBuffer, double pts, double duration) {
		log_debug(@"decoded, pts: %f, duration: %f", pts, duration);
		CFRetain(pixelBuffer);
		dispatch_async(dispatch_get_main_queue(), ^{
			CGImageRef image = [self pixelBufferToImageRef:pixelBuffer];
			_videoLayer.contents = (__bridge id)(image);
			CFRelease(image);
		});
	}];
	
	VideoEncoder *_encoder = [[VideoEncoder alloc] init];
	[_encoder start:^(NSData *nalu, double pts, double duration) {
		log_debug(@"encoded, pts: %f, duration: %f, %d bytes", pts, duration, (int)nalu.length);
		if(!_decoder.isReadyForFrame && _encoder.sps){
			log_debug(@"init decoder");
			[_decoder setSps:_encoder.sps pps:_encoder.pps];
		}
		[_decoder decode:nalu pts:pts duration:duration];
	}];
	
	while(1){
		NSString *file = [NSHomeDirectory() stringByAppendingFormat:@"/Downloads/m1.mp4"];
		VideoReader *reader = [[VideoReader alloc] initWithFile:file];
		CMSampleBufferRef sampleBuffer;
		while(1){
			sampleBuffer = [reader nextSampleBuffer];
			if(!sampleBuffer){
				break;
			}
			[_encoder encodeSampleBuffer:sampleBuffer];
			CFRelease(sampleBuffer);
			usleep(15 * 1000);
		}
	}
}

// CVImageBufferRef 即是 CVPixelBufferRef
- (CGImageRef)pixelBufferToImageRef:(CVImageBufferRef)imageBuffer{
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
												 kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst
												 );
	CGImageRef image = NULL;
	if(context){
		image = CGBitmapContextCreateImage(context);
	}
	CGContextRelease(context);
	CGColorSpaceRelease(colorSpace);
	return image;
}

- (void)stop{
	log_debug(@"stop");
	[_recorder stop];
}

- (int)incr{
	static int i = 0;
	return i++;
}

@end
