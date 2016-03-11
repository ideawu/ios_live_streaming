//
//  AudioBufferQueue.h
//  irtc
//
//  Created by ideawu on 16-3-12.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@interface AudioBufferQueue : NSObject

- (id)initWithAudioQueue:(AudioQueueRef)queue;

- (int)freeCount;
- (int)readyCount;

- (AudioQueueBufferRef)getFreeBuffer;
- (void)pushFreeBuffer;
- (AudioQueueBufferRef)popFreeBuffer;
- (void)pushReadyBuffer:(AudioQueueBufferRef)buffer;
- (AudioQueueBufferRef)popReadyBuffer;

@end
