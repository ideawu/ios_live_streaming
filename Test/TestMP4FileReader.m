//
//  TestMP4File.m
//  irtc
//
//  Created by ideawu on 3/17/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "TestMP4FileReader.h"
#import "MP4FileReader.h"

@implementation TestMP4FileReader

- (id)init{
	self = [super init];
	[self run];
	return self;
}

- (void)run{
	NSString *file = [NSHomeDirectory() stringByAppendingFormat:@"/Downloads/params.mp4"];
	MP4FileReader *reader = [MP4FileReader readerAtPath:file];
	while(1){
		NSData *nalu = [reader nextNALU];
		if(!nalu){
			break;
		}
		log_debug(@"nalu len: %d", (int)nalu.length);
	}
}

@end
