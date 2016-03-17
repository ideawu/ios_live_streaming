//
//  TestAudio.m
//  irtc
//
//  Created by ideawu on 16-3-13.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import "TestAudio.h"
#import "AudioReader.h"
#import "AudioEncoder.h"
#import "AudioDecoder.h"
#import "AudioPlayer.h"

@interface TestAudio(){
	AudioEncoder *encoder;
	AudioDecoder *decoder;
	AudioPlayer *audioPlayer;
}
@end


@implementation TestAudio

- (id)init{
	self = [super init];
	[self run];
	return self;
}

- (void)run{
	encoder = [[AudioEncoder alloc] init];
	decoder = [[AudioDecoder alloc] init];

	int raw_format = 1;
	if(raw_format){
		audioPlayer = [[AudioPlayer alloc] init];
		[audioPlayer setSampleRate:48000 channels:2];
	}else{
		audioPlayer = [AudioPlayer AACPlayerWithSampleRate:48000 channels:2];
	}

	[decoder start:^(NSData *pcm, double duration) {
		//		double pts = 0;
		//		NSLog(@"decoder %d bytes, %f %f", (int)pcm.length, pts, duration);
		[audioPlayer appendData:pcm];
	}];


	[encoder start:^(NSData *aac, double pts, double duration) {
		if(raw_format){
			[decoder decode:aac];
		}else{
			[audioPlayer appendData:aac];
		}
	}];



	while(1){
		//NSString *input = [NSHomeDirectory() stringByAppendingFormat:@"/Downloads/sourcePCM.aif"];
		NSString *input = [NSHomeDirectory() stringByAppendingFormat:@"/Downloads/m1.mp4"];
		AudioReader *reader = [AudioReader readerWithFile:input];

		CMSampleBufferRef sampleBuffer;
		while(1){
			sampleBuffer = [reader nextSampleBuffer];
			if(!sampleBuffer){
				break;
			}
			[encoder encodeSampleBuffer:sampleBuffer];
			CFRelease(sampleBuffer);
			usleep(200 * 1000);
			//break;
		}
	}


	//	reader = [AudioReader readerWithFile:input];
	//	while(1){
	//		NSData *data = [reader nextSampleData];
	//		if(!data){
	//			break;
	//		}
	//		[audioPlayer appendData:data audioFormat:reader.format];
	//	}

}

@end
