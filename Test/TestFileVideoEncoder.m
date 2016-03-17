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

//	NSString *file = [NSHomeDirectory() stringByAppendingFormat:@"/Downloads/m1.mp4"];
//	VideoReader *reader = [[VideoReader alloc] initWithFile:file];
//	CMSampleBufferRef sampleBuffer;
//	int n = 0;
//	while(1){
//		sampleBuffer = [reader nextSampleBuffer];
//		if(!sampleBuffer){
//			break;
//		}
//		n ++;
//		[me onVideoCapturedSampleBuffer:sampleBuffer];
//		CFRelease(sampleBuffer);
//		usleep(100 * 1000);
//	}
//	log_debug(@"write %d frames", n);
//	
//	[_videoEncoder shutdown];

	_capture = [[LiveCapture alloc] init];
	[_capture setupVideo:^(CMSampleBufferRef sampleBuffer) {
		[me onVideoCapturedSampleBuffer:sampleBuffer];
	}];
	
	[_capture start];
}

- (void)onVideoCapturedSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	[_videoEncoder encodeSampleBuffer:sampleBuffer];
}

@end
