//
//  VideoEncoder.h
//  Encoder Demo
//
//  Created by Geraint Davies on 14/01/2013.
//  Copyright (c) 2013 GDCL http://www.gdcl.co.uk/license.htm
//

#import <AVFoundation/AVFoundation.h>

@interface Mp4File : NSObject
{
    AVAssetWriter* _writer;
    AVAssetWriterInput* _writerInput;
    NSString* _path;
}

@property NSString* path;
@property int bitrate;

+ (Mp4File*) videoForPath:(NSString*)path Height:(int)height andWidth:(int)width bitrate:(int)bitrate;

- (void) initPath:(NSString*)path Height:(int) height andWidth:(int) width;
- (void) finishWithCompletionHandler:(void (^)(void))handler;
- (BOOL) encodeFrame:(CMSampleBufferRef) sampleBuffer;


@end
