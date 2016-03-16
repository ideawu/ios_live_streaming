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
#import "FileStreamReader.h"

/**
 before finishWritingWithCompletionHandler, the .mp4 has a
 'mdat' with length header of zero(0x00000000).
 
 when finishWritingWithCompletionHandler, the .mp4 file will
 replace that zero with the exact number
 */

typedef enum{
	ReadStateAtomHeader,
	ReadStateAtomData,
	ReadStateNALUHeader,
	ReadStateNALUData,
}ReadState;

@interface MP4FileVideoEncoder(){
	MP4File *_headerWriter;
	MP4File *_writer;
	int _recordSeq;
	mp4_reader *_mp4;
	FileStreamReader *_reader;
	ReadState _state;
}
@end


@implementation MP4FileVideoEncoder

- (id)init{
	self = [super init];
	_width = 480;
	_height = 640;
	_mp4 = NULL;
	_state = ReadStateAtomHeader;
	return self;
}

- (void)dealloc{
	if(_mp4){
		mp4_reader_free(_mp4);
	}
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
	if(!_mp4){
		[self createReader];
	}
	[_reader refresh];
	[self parse];
}

- (void)createReader{
	_mp4 = mp4_reader_init();
	_mp4->user_data = (__bridge void *)(self);
	_mp4->input_cb = my_mp4_input_cb;
	_reader = [FileStreamReader readerForFile:_writer.path];
	log_debug(@"create mp4 reader for file: %@", _writer.path.lastPathComponent);
}

static int my_mp4_input_cb(mp4_reader *mp4, void *buf, int size){
	MP4FileVideoEncoder *me = (__bridge MP4FileVideoEncoder *)mp4->user_data;
	[me readFileData:buf size:size];
	return size;
}

- (void)readFileData:(void *)buf size:(int)size{
	if(buf){
		[_reader read:buf size:size];
	}else{
		[_reader skip:size];
	}
}

- (void)finishParse{
	// read the new length of 'mdat'
	mp4_reader *mp4 = mp4_file_open(_writer.path.UTF8String);
	if(!mp4){
		log_error(@"failed to open %@ after finish writting.", _writer.path.lastPathComponent);
		return;
	}
	
	uint32_t type;
	long size;
	while(mp4_reader_next_atom(mp4)){
		type = mp4->atom->type;
		size = mp4->atom->size;
		if(type == 'mdat'){
		}
	}
	mp4_reader_free(mp4);
	
	[self onFileUpdate];
}

- (void)parse{
	while(1){
		if(_state == ReadStateAtomHeader){
			if(_reader.available < 8){
				return;
			}
			if(mp4_reader_next_atom(_mp4)){
				if(_mp4->atom->type == 'mdat'){
					log_debug(@"found mdat");
					_state = ReadStateNALUHeader;
					if(_mp4->atom->size == 0){
						exit(0);
					}
				}else{
					// skip this atom
					_state = ReadStateAtomData;
				}
			}else{
				log_error(@"file end?");
				return;
			}
		}else if(_state == ReadStateAtomData){
			if(_reader.available < _mp4->atom->size){
				return;
			}
			_state = ReadStateAtomHeader;
			mp4_reader_skip_atom_data(_mp4);
		}else if(_state == ReadStateNALUHeader){
			if(_reader.available < 4){
				return;
			}
			if(mp4_reader_next_nalu(_mp4)){
				_state = ReadStateNALUData;
			}else{
				log_debug(@"read mdat end");
				_state = ReadStateAtomHeader;
			}
		}else if(_state == ReadStateNALUData){
			if(_reader.available < _mp4->nalu->size){
				return;
			}
			_state = ReadStateNALUHeader;

			int length = (int)_mp4->nalu->length;
			uint32_t hdr = htonl((uint32_t)_mp4->nalu->size);
			void *buf = malloc(length);
			memcpy(buf, &hdr, 4);
			mp4_reader_read_nalu_data(_mp4, buf+4, length-4);
			
			NSData *nalu = [NSData dataWithBytesNoCopy:buf length:length freeWhenDone:YES];
			log_debug(@"found nalu, length: %d", (int)nalu.length);
			static int n = 0;
			n++;
			log_debug(@"%d nalus", n);
		}
	}
}

@end
