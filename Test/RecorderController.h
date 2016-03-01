//
//  RecorderController.h
//  VideoTest
//
//  Created by ideawu on 12/16/15.
//  Copyright © 2015 ideawu. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface RecorderController : NSWindowController
@property (weak) IBOutlet NSView *videoView;
- (IBAction)start:(id)sender;
- (IBAction)stop:(id)sender;

@end
