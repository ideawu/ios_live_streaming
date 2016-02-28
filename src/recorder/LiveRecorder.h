//
//  LiveRecorder.h
//  recorder
//
//  Created by ideawu on 16-2-28.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LiveRecorder : NSObject

@property (nonatomic, readonly) AVCaptureSession *session;
@property (nonatomic) double chunkDuration;

- (void)start:(void (^)(NSData *))chunkCallback;
- (void)stop;

@end
