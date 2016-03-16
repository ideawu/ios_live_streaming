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

	NSString *file = [NSHomeDirectory() stringByAppendingFormat:@"/Downloads/m1.mp4"];
	VideoReader *reader = [[VideoReader alloc] initWithFile:file];
	CMSampleBufferRef sampleBuffer;
	while(1){
		sampleBuffer = [reader nextSampleBuffer];
		if(!sampleBuffer){
			break;
		}
		[me onVideoCapturedSampleBuffer:sampleBuffer];
		CFRelease(sampleBuffer);
		usleep(30 * 1000);
	}

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
