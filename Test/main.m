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

int main(int argc, const char * argv[]) {

#if 0
	audioPlayer = [[AudioPlayer alloc] init];
	[audioPlayer setSampleRate:48000 channels:2];

	AudioEncoder *encoder = [[AudioEncoder alloc] init];
	AudioDecoder *decoder = [[AudioDecoder alloc] init];

	
	[decoder start:^(NSData *pcm, double duration) {
		double pts = 0;
		NSLog(@"decoder %d bytes, %f %f", (int)pcm.length, pts, duration);
		[audioPlayer appendData:pcm];
	}];


//	audioPlayer = [AudioPlayer AACPlayerWithSampleRate:48000 channels:2];

	[encoder start:^(NSData *aac, double duration) {
		double pts = 0;
		NSLog(@"encoder %d bytes, %f %f", (int)aac.length, pts, duration);
		
//		int adts_header = 7;
//		NSData *aac = [NSData dataWithBytes:data.bytes+adts_header
//									 length:data.length-adts_header];
//		[audioPlayer appendData:aac];
		[decoder decode:aac];
	}];
	

	
	NSString *input = [NSHomeDirectory() stringByAppendingFormat:@"/Downloads/sourcePCM.aif"];
	AudioReader *reader = [AudioReader readerWithFile:input];
	
	CMSampleBufferRef sampleBuffer;
	while(1){
		sampleBuffer = [reader nextSampleBuffer];
		if(!sampleBuffer){
			break;
		}
		[encoder encodeSampleBuffer:sampleBuffer];
		CFRelease(sampleBuffer);
		usleep(100 * 1000);
		//break;
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
	sleep(15);
#else
	return NSApplicationMain(argc, argv);
#endif
}
