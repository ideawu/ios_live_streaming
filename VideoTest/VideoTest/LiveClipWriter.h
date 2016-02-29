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

@property (nonatomic, readonly) AVAssetWriter *writer;
@property (nonatomic, readonly) int frameCount;
@property (nonatomic, readonly) double duration;
@property (nonatomic, readonly) double startTime;
@property (nonatomic, readonly) double endTime;

- (id)initWithFilename:(NSString *)filename;

- (void)encodeAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (void)encodeVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (void)finishWritingWithCompletionHandler:(void (^)())handler;

@end
