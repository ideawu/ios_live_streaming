//
//  Mp4FileVideoEncoder.m
//  irtc
//
//  Created by ideawu on 3/16/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "Mp4FileVideoEncoder.h"
#import "MP4File.h"
#import "mp4_reader.h"

@interface MP4FileVideoEncoder(){
	MP4File *_headerWriter;
	MP4File *_writer;
	int _recordSeq;
	mp4_reader *_mp4;
}
@end


@implementation MP4FileVideoEncoder

- (id)init{
	self = [super init];
	_width = 480;
	_height = 640;
	_mp4 = NULL;
	return self;
}

- (void)dealloc{
	if(_mp4){
		mp4_reader_free(_mp4);
	}
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

	CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
	log_debug(@"width: %d, height: %d, %d bytes",
			  (int)CVPixelBufferGetWidth(imageBuffer),
			  (int)CVPixelBufferGetHeight(imageBuffer),
			  (int)CVPixelBufferGetDataSize(imageBuffer)
			  );

	if(!_headerWriter){
		NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"params.mp4"];
		_headerWriter = [MP4File videoForPath:path Height:_height andWidth:_width bitrate:0];
		if([_headerWriter encodeFrame:sampleBuffer]){
			[_headerWriter finishWithCompletionHandler:^{
				[me parseHeaderFile];
			}];
		}
	}
	
	if(!_writer){
		NSString *path = [self nextFilename];
		_writer = [MP4File videoForPath:path Height:_height andWidth:_width bitrate:0];
	}
	[_writer encodeFrame:sampleBuffer];
	
	@synchronized(self){
		if(_sps){
			[self parseNALU];
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

- (void)parseNALU{
	log_debug(@"parse");
	const char *filename = _writer.path.UTF8String;
	if(!_mp4){
		_mp4 = mp4_file_open(filename);
		if(!_mp4){
			log_error(@"failed to open %s", filename);
			return;
		}
		while(mp4_reader_next_atom(_mp4)){
			if(_mp4->atom->type == 'mdat'){
				log_debug(@"found mdat");
				break;
			}
		}
	}
	
	while(mp4_reader_next_nalu(_mp4)){
		//
	}
}

@end
