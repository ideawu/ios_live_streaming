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

@interface AppDelegate (){
	PlayerController *_player;
	RecorderController *_recorder;
}

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	// Insert code here to initialize your application
	_player = [[PlayerController alloc] initWithWindowNibName:@"PlayerController"];
	[_player showWindow:self];

	_recorder = [[RecorderController alloc] initWithWindowNibName:@"RecorderController"];
	//[_recorder showWindow:self];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
	// Insert code here to tear down your application
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender{
	return YES;
}

@end
