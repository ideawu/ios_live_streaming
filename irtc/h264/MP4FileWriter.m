//
//  VideoEncoder.m
//  Encoder Demo
//
//  Created by Geraint Davies on 14/01/2013.
//  Copyright (c) 2013 GDCL http://www.gdcl.co.uk/license.htm
//

#import "MP4FileWriter.h"

@interface MP4FileWriter(){
	BOOL _sessionStarted;
}
@end


@implementation MP4FileWriter

+ (MP4FileWriter*)videoForPath:(NSString*)path Height:(int)height andWidth:(int)width bitrate:(int)bitrate{
    MP4FileWriter* enc = [MP4FileWriter alloc];
	enc.bitrate = bitrate;
    [enc initPath:path Height:height andWidth:width];
    return enc;
}

- (void)initPath:(NSString*)path Height:(int) height andWidth:(int) width{
    self.path = path;
	log_debug(@"encoder %@", path);

    [[NSFileManager defaultManager] removeItemAtPath:self.path error:nil];
    NSURL* url = [NSURL fileURLWithPath:self.path];
	
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
	
	_sessionStarted = NO;
	[_writer startWriting];
}

- (void)finishWithCompletionHandler:(void (^)(void))handler{
    [_writer finishWritingWithCompletionHandler: handler];
}

- (BOOL)encodeSampleBuffer:(CMSampleBufferRef) sampleBuffer{
    if (CMSampleBufferDataIsReady(sampleBuffer)){
		if(!_sessionStarted){
			_sessionStarted = YES;
            CMTime startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
            [_writer startSessionAtSourceTime:startTime];
        }
        if (_writer.status == AVAssetWriterStatusFailed){
            log_debug(@"writer error %@", _writer.error.localizedDescription);
            return NO;
        }
        if (_writerInput.readyForMoreMediaData == YES){
            [_writerInput appendSampleBuffer:sampleBuffer];
            return YES;
        }
	}
    return NO;
}

@end
