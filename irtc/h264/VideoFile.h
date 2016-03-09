//
//  VideoEncoder.h
//  Encoder Demo
//
//  Created by Geraint Davies on 14/01/2013.
//  Copyright (c) 2013 GDCL http://www.gdcl.co.uk/license.htm
//

#import <Foundation/Foundation.h>
#import "AVFoundation/AVAssetWriter.h"
#import "AVFoundation/AVAssetWriterInput.h"
#import "AVFoundation/AVMediaFormat.h"
#import "AVFoundation/AVVideoSettings.h"

@interface VideoFile : NSObject
{
    AVAssetWriter* _writer;
    AVAssetWriterInput* _writerInput;
    NSString* _path;
}

@property NSString* path;
@property int bitrate;

+ (VideoFile*) videoForPath:(NSString*)path Height:(int)height andWidth:(int)width bitrate:(int)bitrate;

- (void) initPath:(NSString*)path Height:(int) height andWidth:(int) width;
- (void) finishWithCompletionHandler:(void (^)(void))handler;
- (BOOL) encodeFrame:(CMSampleBufferRef) sampleBuffer;


@end
