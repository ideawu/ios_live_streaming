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

@interface AppDelegate (){
	NSWindowController *_test;
}

@property (weak) IBOutlet NSWindow *window;
@property (nonatomic) TestFileVideoEncoder *fileVideoEncoder;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	NSLog(@"NSTemporaryDirectory: %@", NSTemporaryDirectory());
	
	int count = 0;
	int flag = 3;
	
	if(flag == count++){
//		_test = [[PlayerController alloc] initWithWindowNibName:@"PlayerController"];
//		[_test showWindow:self];
	}
	if(flag == count++){
//		_test = [[RecorderController alloc] initWithWindowNibName:@"RecorderController"];
//		[_test showWindow:self];
	}
	if(flag == count++){
		_test = [[TestController alloc] initWithWindowNibName:@"TestController"];
	}
	if(flag == count++){
		_test = [[TestFileVideoEncoder alloc] initWithWindowNibName:@"TestFileVideoEncoder"];
	}
	
	[_test showWindow:self];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
	// Insert code here to tear down your application
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender{
	return YES;
}

@end
