//
//  PlayerController.h
//  VideoTest
//
//  Created by ideawu on 12/11/15.
//  Copyright © 2015 ideawu. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface PlayerController : NSWindowController
@property (weak) IBOutlet NSView *previewView;
@property (weak) IBOutlet NSButton *playBtn;
- (IBAction)onPlay:(id)sender;
- (IBAction)onNextFrame:(id)sender;
- (IBAction)onLoad:(id)sender;
- (IBAction)prevFrame:(id)sender;
- (IBAction)onNextSkip:(id)sender;
- (IBAction)onPrevSkip:(id)sender;

@end
