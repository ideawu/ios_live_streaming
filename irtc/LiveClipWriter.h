//
//  AVEncoder.h
//  VideoTest
//
//  Created by ideawu on 12/18/15.
//  Copyright © 2015 ideawu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface LiveClipWriter : NSObject

// TODO: status

@property (nonatomic, readonly) int frameCount;
@property (nonatomic, readonly) double duration;
@property (nonatomic, readonly) int audioFrameCount;

- (id)initWithFilename:(NSString *)filename videoWidth:(int)width videoHeight:(int)height;

- (void)encodeAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (void)encodeVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer;

- (void)finishWritingWithCompletionHandler:(void (^)(NSData *))handler;

@end
