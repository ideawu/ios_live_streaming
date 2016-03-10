//
//  main.m
//  Test
//
//  Created by ideawu on 3/1/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "AudioFile.h"
#import "AudioReader.h"
#import "AudioEncoder.h"

int main(int argc, const char * argv[]) {
#if 1
	AudioEncoder *encoder = [[AudioEncoder alloc] init];
	[encoder encodeWithBlock:^(NSData *data, double pts, double duration) {
		NSLog(@"%d bytes, %f %f", (int)data.length, pts, duration);
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
	}
	NSLog(@"end");
	sleep(1);
#else
	return NSApplicationMain(argc, argv);
#endif
}
