//
//  VideoEncoder.m
//  Encoder Demo
//
//  Created by Geraint Davies on 14/01/2013.
//  Copyright (c) 2013 GDCL http://www.gdcl.co.uk/license.htm
//

#import "Mp4File.h"

@implementation Mp4File

+ (Mp4File*)videoForPath:(NSString*)path Height:(int)height andWidth:(int)width bitrate:(int)bitrate{
    Mp4File* enc = [Mp4File alloc];
	enc.bitrate = bitrate;
    [enc initPath:path Height:height andWidth:width];
    return enc;
}


- (void) initPath:(NSString*)path Height:(int) height andWidth:(int) width{
    self.path = path;

    [[NSFileManager defaultManager] removeItemAtPath:self.path error:nil];
    NSURL* url = [NSURL fileURLWithPath:self.path];
	
	NSLog(@"encoder %@", url.absoluteString);
    _writer = [AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeMPEG4 error:nil];
	NSMutableDictionary *cs = [[NSMutableDictionary alloc] init];
	if(_bitrate > 0){
		[cs setObject:@(_bitrate) forKey:AVVideoAverageBitRateKey];
	}
#if DEBUG
	[cs setObject:@(20) forKey:AVVideoMaxKeyFrameIntervalKey];
#else
	[cs setObject:@(90) forKey:AVVideoMaxKeyFrameIntervalKey];
#endif
#if !TARGET_OS_MAC
	[cs setObject:@(NO) forKey:AVVideoAllowFrameReorderingKey];
#else
#ifdef NSFoundationVersionNumber10_10
	if(NSFoundationVersionNumber >= NSFoundationVersionNumber10_10){
		[cs setObject:@(NO) forKey:AVVideoAllowFrameReorderingKey];
	}
#endif
#endif
	//AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel, // failed OS X 10.10+
	NSDictionary* settings;
	settings = @{
				 AVVideoCodecKey: AVVideoCodecH264,
				 AVVideoWidthKey: @(width),
				 AVVideoHeightKey: @(height),
				 AVVideoCompressionPropertiesKey: cs,
				 };
    _writerInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:settings];
    _writerInput.expectsMediaDataInRealTime = YES;
    [_writer addInput:_writerInput];
}

- (void) finishWithCompletionHandler:(void (^)(void))handler
{
    [_writer finishWritingWithCompletionHandler: handler];
}

- (BOOL) encodeFrame:(CMSampleBufferRef) sampleBuffer
{
    if (CMSampleBufferDataIsReady(sampleBuffer))
    {
        if (_writer.status == AVAssetWriterStatusUnknown)
        {
            CMTime startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
            [_writer startWriting];
            [_writer startSessionAtSourceTime:startTime];
        }
        if (_writer.status == AVAssetWriterStatusFailed)
        {
            NSLog(@"writer error %@", _writer.error.localizedDescription);
            return NO;
        }
        if (_writerInput.readyForMoreMediaData == YES)
        {
            [_writerInput appendSampleBuffer:sampleBuffer];
            return YES;
        }
    }
    return NO;
}

@end
