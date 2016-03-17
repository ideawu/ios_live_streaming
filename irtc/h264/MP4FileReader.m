//
//  MP4FileReader.m
//  irtc
//
//  Created by ideawu on 16-3-17.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import "MP4FileReader.h"
#import "FileReader.h"
#import "mp4_reader.h"

typedef enum{
	ReadStateAtomHeader,
	ReadStateAtomData,
	ReadStateAtomDataReady,
	ReadStateNALUHeader,
	ReadStateNALUData,
	ReadStateNALUDataReady,
}ReadState;

@interface MP4FileReader(){
	mp4_reader *_mp4;
	ReadState _state;
	int64_t _mdat_pos;
}
@property FileReader *file;
@end

@implementation MP4FileReader

+ (MP4FileReader *)readerAtPath:(NSString *)path{
	MP4FileReader *ret = [[MP4FileReader alloc] init];
	ret.file = [FileReader readerAtPath:path];
	[ret createMP4Reader];
	return ret;
}

- (id)init{
	self = [super init];
	_state = ReadStateAtomHeader;
	_mdat_pos = 0;
	_mp4 = NULL;
	return self;
}

- (void)dealloc{
	if(_mp4){
		mp4_reader_free(_mp4);
	}
}

- (void)refresh{
	[_file refresh];
}

- (void)reloadMDATLength{
	long pos = _file.offset;
	long mdat_read = pos - _mdat_pos;
	uint32_t length;
	
	[_file seekTo:_mdat_pos];
	[_file read:&length size:4];
	[_file seekTo:pos];
	//log_debug(@"offset: %d, total: %d, available: %d", _reader.offset, _reader.total, _reader.available);
	length = ntohl(length);
	_mp4->atom->size = length - mdat_read + _mp4->nalu->length; // remember to add current nalu's length
}

- (NSData *)nextNALU{
	do{
		if(![self parse]){
			return nil;
		}
	}while(_state != ReadStateNALUDataReady);

	int length = (int)_mp4->nalu->length;
	uint32_t hdr = htonl((uint32_t)_mp4->nalu->size);
	void *buf = malloc(length);
	memcpy(buf, &hdr, 4);
	mp4_reader_read_nalu_data(_mp4, buf+4, length-4);

	NSData *nalu = [NSData dataWithBytesNoCopy:buf length:length freeWhenDone:YES];
	return nalu;
}

/**
 return YES indates state changed
 return NO indates need more data
 */
- (BOOL)parse{
	if(_state == ReadStateAtomHeader){
		if(_file.available < 8){
			return NO;
		}
		if(mp4_reader_next_atom(_mp4)){
			if(_mp4->atom->type == 'mdat'){
				log_debug(@"found mdat");
				_state = ReadStateNALUHeader;
				// we will re-read mdat length after finish writting
				_mdat_pos = _file.offset - 8;
			}else{
				// skip this atom
				_state = ReadStateAtomData;
			}
		}else{
			log_debug(@"file end");
			return NO;
		}
	}else if(_state == ReadStateAtomData){
		if(_file.available < _mp4->atom->size){
			return NO;
		}
		_state = ReadStateAtomDataReady;
	}else if(_state == ReadStateAtomDataReady){
		_state = ReadStateAtomHeader;
	}else if(_state == ReadStateNALUHeader){
		if(_file.available < 4){
			return NO;
		}
		if(mp4_reader_next_nalu(_mp4)){
			_state = ReadStateNALUData;
		}else{
			log_debug(@"read mdat end");
			_state = ReadStateAtomHeader;
		}
	}else if(_state == ReadStateNALUData){
		if(_file.available < _mp4->nalu->size){
			return NO;
		}
		_state = ReadStateNALUDataReady;
	}else if(_state == ReadStateNALUDataReady){
		_state = ReadStateNALUHeader;
	}
	return YES;
}

- (void)createMP4Reader{
	_mp4 = mp4_reader_init();
	_mp4->user_data = (__bridge void *)(self);
	_mp4->input_cb = my_mp4_input_cb;
	log_debug(@"create mp4 reader for file: %@", _file.path.lastPathComponent);
}

static int my_mp4_input_cb(mp4_reader *mp4, void *buf, int size){
	MP4FileReader *me = (__bridge MP4FileReader *)mp4->user_data;
	return [me readFileData:buf size:size];
}

- (int)readFileData:(void *)buf size:(int)size{
	if(_file.available < size){
		return 0;
	}
	if(buf){
		[_file read:buf size:size];
	}else{
		[_file skip:size];
	}
	return size;
}

@end
