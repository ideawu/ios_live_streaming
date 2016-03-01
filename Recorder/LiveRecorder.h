//
//  LiveRecorder.h
//  recorder
//
//  Created by ideawu on 16-2-28.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface LiveRecorder : NSObject

@property (nonatomic, readonly) AVCaptureSession *session;
@property (nonatomic) double chunkDuration;

+ (LiveRecorder *)recorderForWidth:(int)width height:(int)height;

- (void)setVideoOrientation:(UIInterfaceOrientation)orientation;

- (void)start:(void (^)(NSData *data))chunkCallback;
- (void)stop;

@end
