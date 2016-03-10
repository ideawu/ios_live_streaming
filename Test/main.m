//
//  main.m
//  Test
//
//  Created by ideawu on 3/1/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "AudioReader.h"
#import "AudioEncoder.h"
#import "AudioPlayer.h"

AudioPlayer *audioPlayer;
AudioStreamBasicDescription format;

void MyAudioQueueIsRunningCallback(void*					inClientData,
								   AudioQueueRef			inAQ,
								   AudioQueuePropertyID	inID)
{
	UInt32 running;
	UInt32 size;
	OSStatus err = AudioQueueGetProperty(inAQ, kAudioQueueProperty_IsRunning, &running, &size);
	if (err) { NSLog(@"get kAudioQueueProperty_IsRunning"); return; }
}

int main(int argc, const char * argv[]) {
#if 1
	
	audioPlayer = [[AudioPlayer alloc] init];
	
	AudioStreamBasicDescription _format;
//	_format.mFormatID = kAudioFormatLinearPCM;
//	_format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	_format.mFormatID = kAudioFormatMPEG4AAC;
	_format.mFormatFlags = kMPEG4Object_AAC_LC;
	_format.mChannelsPerFrame = 2;
	_format.mSampleRate = 48000.0;
	_format.mFramesPerPacket = 1024;
//	_format.mBitsPerChannel = 16;
//	_format.mBytesPerPacket = _format.mChannelsPerFrame * (_format.mBitsPerChannel / 8);
//	_format.mBytesPerFrame = _format.mBytesPerPacket;
	
	AudioEncoder *encoder = [[AudioEncoder alloc] init];
	[encoder encodeWithBlock:^(NSData *data, double pts, double duration) {
		NSLog(@"%d bytes, %f %f", (int)data.length, pts, duration);

		int adts_header = 7;
		NSData *aac = [NSData dataWithBytes:data.bytes+adts_header
									 length:data.length-adts_header];
		[audioPlayer appendData:aac audioFormat:_format];
	}];
	
	NSString *input = [NSTemporaryDirectory() stringByAppendingFormat:@"/a.aif"];
	AudioReader *reader = [AudioReader readerWithFile:input];
	CMSampleBufferRef sampleBuffer;
	while(1){
		sampleBuffer = [reader nextSampleBuffer];
		if(!sampleBuffer){
			break;
		}
		[encoder encodeSampleBuffer:sampleBuffer];
		CFRelease(sampleBuffer);
		//usleep(100 * 1000);
	}
	
//	reader = [AudioReader readerWithFile:input];
//	while(1){
//		NSData *data = [reader nextSampleData];
//		if(!data){
//			break;
//		}
//		[audioPlayer appendData:data audioFormat:reader.format];
//	}

	NSLog(@"end");
	sleep(10);
#else
	return NSApplicationMain(argc, argv);
#endif
}
