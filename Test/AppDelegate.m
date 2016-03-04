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
#import "VideoRecorder.h"

@interface AppDelegate (){
	PlayerController *_player;
	RecorderController *_recorder;
	VideoRecorder *_vr;
}

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	NSLog(@"NSTemporaryDirectory: %@", NSTemporaryDirectory());
	// Insert code here to initialize your application
//	_player = [[PlayerController alloc] initWithWindowNibName:@"PlayerController"];
//	_recorder = [[RecorderController alloc] initWithWindowNibName:@"RecorderController"];
//
//	[_player showWindow:self];
//	[_recorder showWindow:self];
	
	_vr = [[VideoRecorder alloc] init];
	[_vr start];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
	// Insert code here to tear down your application
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender{
	return YES;
}

@end
