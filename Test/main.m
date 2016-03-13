//
//  main.m
//  Test
//
//  Created by ideawu on 3/1/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "TestAudio.h"
#import "TestVideo.h"

int main(int argc, const char * argv[]) {
#if 1
	TestVideo *test = [[TestVideo alloc] init];
	NSLog(@"end");
	sleep(15);
	test = nil;
#else
	return NSApplicationMain(argc, argv);
#endif
}
