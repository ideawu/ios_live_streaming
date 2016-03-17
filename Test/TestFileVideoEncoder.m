//
//  TestFileVideoEncoder.m
//  irtc
//
//  Created by ideawu on 3/16/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "TestFileVideoEncoder.h"
#import "LiveCapture.h"
#import "MP4FileVideoEncoder.h"
#import "VideoReader.h"

@interface TestFileVideoEncoder (){
	
}
@property (nonatomic) LiveCapture *capture;
@property (nonatomic) MP4FileVideoEncoder *videoEncoder;
@end

@implementation TestFileVideoEncoder

- (void)windowDidLoad {
	[super windowDidLoad];
	__weak typeof(self) me = self;
	
	_videoEncoder = [[MP4FileVideoEncoder alloc] init];

	int count = 0;
	for(int i=0; i<10; i++){
		NSString *file = [NSHomeDirectory() stringByAppendingFormat:@"/Downloads/m1.mp4"];
		VideoReader *reader = [[VideoReader alloc] initWithFile:file];
		CMSampleBufferRef sampleBuffer;
		int n = 0;
		while(1){
			sampleBuffer = [reader nextSampleBuffer];
			if(!sampleBuffer){
				break;
			}
			
			CMSampleTimingInfo time;
			double frameDuration = 1.0/30;
			time.presentationTimeStamp = CMTimeMakeWithSeconds(count * frameDuration, 6000);
			time.duration = CMTimeMakeWithSeconds(frameDuration, 6000);
			
			CMSampleBufferRef newSampleBuffer;
			CMSampleBufferCreateCopyWithNewTiming(kCFAllocatorDefault,
												  sampleBuffer,
												  1,
												  &time,
												  &newSampleBuffer);
			CFRelease(sampleBuffer);
			sampleBuffer = newSampleBuffer;
			
			n ++;
			count ++;
			[me onVideoCapturedSampleBuffer:sampleBuffer];
			CFRelease(sampleBuffer);
			usleep(100 * 1000);
		}
		log_debug(@"write %d frames", n);
	}
	
	[_videoEncoder shutdown];

//	_capture = [[LiveCapture alloc] init];
//	[_capture setupVideo:^(CMSampleBufferRef sampleBuffer) {
//		[me onVideoCapturedSampleBuffer:sampleBuffer];
//	}];
	
	[_capture start];
}

- (void)onVideoCapturedSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	[_videoEncoder encodeSampleBuffer:sampleBuffer];
}

@end
