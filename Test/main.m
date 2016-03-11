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
#import "AudioDecoder.h"
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
	
	AudioEncoder *encoder = [[AudioEncoder alloc] init];
	AudioDecoder *decoder = [[AudioDecoder alloc] init];
	
	[decoder start:^(NSData *pcm, double duration) {
		double pts = 0;
		NSLog(@"decoder %d bytes, %f %f", (int)pcm.length, pts, duration);
	}];
	
//	[encoder start:^(NSData *aac, double duration) {
//		double pts = 0;
//		NSLog(@"encoder %d bytes, %f %f", (int)aac.length, pts, duration);
//		
//		//[decoder decode:aac];
//
////		int adts_header = 7;
////		NSData *aac = [NSData dataWithBytes:data.bytes+adts_header
////									 length:data.length-adts_header];
////		[audioPlayer appendData:aac audioFormat:_format];
//	}];
//	
//	NSString *input = [NSTemporaryDirectory() stringByAppendingFormat:@"/a.aif"];
//	AudioReader *reader = [AudioReader readerWithFile:input];
//	CMSampleBufferRef sampleBuffer;
//	while(1){
//		sampleBuffer = [reader nextSampleBuffer];
//		if(!sampleBuffer){
//			break;
//		}
//		[encoder encodeSampleBuffer:sampleBuffer];
//		CFRelease(sampleBuffer);
//		//usleep(100 * 1000);
//	}
	
//	reader = [AudioReader readerWithFile:input];
//	while(1){
//		NSData *data = [reader nextSampleData];
//		if(!data){
//			break;
//		}
//		[audioPlayer appendData:data audioFormat:reader.format];
//	}

	NSLog(@"end");
//	sleep(10);
#else
	return NSApplicationMain(argc, argv);
#endif
}
