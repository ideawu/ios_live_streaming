//
//  AppDelegate.m
//  VideoTest
//
//  Created by ideawu on 12/11/15.
//  Copyright © 2015 ideawu. All rights reserved.
//

#import "AppDelegate.h"
#import "PlayerController.h"
#import "RecorderController.h"
#import "TestController.h"
#import "TestFileVideoEncoder.h"
#import "TestMP4FileReader.h"
#import "TestAudio.h"
#import "TestVideo.h"
#import "TestRecorder.h"

@interface AppDelegate (){
	id _test;
}

@property (weak) IBOutlet NSWindow *window;
@property (nonatomic) TestFileVideoEncoder *fileVideoEncoder;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	NSLog(@"NSTemporaryDirectory: %@", NSTemporaryDirectory());
	
	int flag = 4;
	
	if(flag == 1){
//		_test = [[PlayerController alloc] initWithWindowNibName:@"PlayerController"];
//		[_test showWindow:self];
	}
	if(flag == 2){
//		_test = [[RecorderController alloc] initWithWindowNibName:@"RecorderController"];
//		[_test showWindow:self];
	}
	if(flag == 3){
		_test = [[TestController alloc] initWithWindowNibName:@"TestController"];
	}
	if(flag == 4){
		_test = [[TestFileVideoEncoder alloc] initWithWindowNibName:@"TestFileVideoEncoder"];
	}
	if(flag == 5){
		_test = [[TestMP4FileReader alloc] init];
	}
	if(flag == 6){
		_test = [[TestAudio alloc] init];
	}
	if(flag == 7){
		_test = [[TestVideo alloc] init];
	}
	if(flag == 8){
		_test = [[TestRecorder alloc] init];
	}
	
	if([_test isKindOfClass:[NSWindowController class]]){
		[_test showWindow:self];
	}
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
	// Insert code here to tear down your application
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender{
	return YES;
}

@end
