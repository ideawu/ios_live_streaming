//
//  Mp4FileVideoEncoder.m
//  irtc
//
//  Created by ideawu on 3/16/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "Mp4FileVideoEncoder.h"
#import "MP4FileWriter.h"
#import "MP4FileReader.h"
#import "mp4_reader.h"

@interface MP4FileVideoEncoder(){
	MP4FileWriter *_headerWriter;
	MP4FileWriter *_writer;

	MP4FileReader *_reader;
	
	int _recordSeq;
	void (^_callback)(NSData *frame, double pts, double duration);
}
@end


@implementation MP4FileVideoEncoder

- (id)init{
	self = [super init];
	_width = 480;
	_height = 640;
	return self;
}

- (void)start:(void (^)(NSData *frame, double pts, double duration))callback{
	_callback = callback;
}

- (void)shutdown{
	[_writer finishWithCompletionHandler:^{
		log_debug(@"finish completion");
		[self finishParse];
	}];
}

- (NSString *)nextFilename{
	NSString *name = [NSString stringWithFormat:@"m%03d.mp4", _recordSeq];
	if(++_recordSeq >= 9){
		_recordSeq = 0;
	}
	return [NSTemporaryDirectory() stringByAppendingPathComponent:name];
}

- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	__weak typeof(self) me = self;

//	CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
//	log_debug(@"width: %d, height: %d, %d bytes",
//			  (int)CVPixelBufferGetWidth(imageBuffer),
//			  (int)CVPixelBufferGetHeight(imageBuffer),
//			  (int)CVPixelBufferGetDataSize(imageBuffer)
//			  );

	if(!_headerWriter){
		NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"params.mp4"];
		_headerWriter = [MP4FileWriter videoForPath:path Height:_height andWidth:_width bitrate:0];
		if([_headerWriter encodeSampleBuffer:sampleBuffer]){
			[_headerWriter finishWithCompletionHandler:^{
				[me parseHeaderFile];
			}];
		}
	}
	
	if(!_writer){
		NSString *path = [self nextFilename];
		_writer = [MP4FileWriter videoForPath:path Height:_height andWidth:_width bitrate:0];
	}
	[_writer encodeSampleBuffer:sampleBuffer];
	
	@synchronized(self){
		if(_sps){
			[self onFileUpdate];
		}
	}
}

- (void)parseHeaderFile{
	void *sps, *pps;
	int sps_size, pps_size;

	const char *filename = _headerWriter.path.UTF8String;
	mp4_file_parse_params(filename, &sps, &sps_size, &pps, &pps_size);
	
	if(sps){
		_sps = [NSData dataWithBytesNoCopy:sps length:sps_size freeWhenDone:YES];
	}
	if(pps){
		_pps = [NSData dataWithBytesNoCopy:pps length:pps_size freeWhenDone:YES];
	}

	if(!_sps || !_pps){
		log_error(@"failed to parse sps and pps!");
		return;
	}
	NSLog(@"sps: %@, pps: %@", _sps, _pps);
}

- (void)onFileUpdate{
	if(!_reader){
		_reader = [MP4FileReader readerAtPath:_writer.path];
	}
	[_reader refresh];
	while(1){
		NSData *nalu = [_reader nextNALU];
		if(!nalu){
			break;
		}
		log_debug(@"nalu len: %d", (int)nalu.length);
	}
}

- (void)finishParse{
	/**
	 before finishWritingWithCompletionHandler, the .mp4 has a
	 'mdat' with length header of zero(0x00000000).
	 
	 when finishWritingWithCompletionHandler, the .mp4 file will
	 replace that zero with the exact number
	 */
	[_reader reloadMDATLength];
	
	[self onFileUpdate];
}

@end
