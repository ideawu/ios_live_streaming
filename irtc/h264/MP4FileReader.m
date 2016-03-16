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
@property FileReader *reader;
@end

@implementation MP4FileReader

+ (MP4FileReader *)readerWithFile:(NSString *)file{
	MP4FileReader *ret = [[MP4FileReader alloc] init];
	ret.reader = [FileReader readerWithFile:file];
	return ret;
}

- (id)init{
	self = [super init];
	_state = ReadStateAtomHeader;
	return self;
}

- (BOOL)before:(ReadState)src after:(ReadState)dst{
	while(_state != src){
		if(![self parse]){
			return NO;
		}
	}
	if(![self parse]){
		return NO;
	}
	if(_state != dst){
		return NO;
	}
	return YES;
}

- (NSData *)nextNALU{
	while(_state != ReadStateNALUDataReady){
		if(![self parse]){
			return NO;
		}
	}

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
		if(_reader.available < 8){
			return NO;
		}
		if(mp4_reader_next_atom(_mp4)){
			if(_mp4->atom->type == 'mdat'){
				log_debug(@"found mdat");
				_state = ReadStateNALUHeader;
				// we will re-read mdat length after finish writting
				_mdat_pos = _reader.offset - 8;
			}else{
				// skip this atom
				_state = ReadStateAtomData;
			}
		}else{
			log_debug(@"file end");
			return NO;
		}
	}else if(_state == ReadStateAtomData){
		if(_reader.available < _mp4->atom->size){
			return NO;
		}
		_state = ReadStateAtomDataReady;
	}else if(_state == ReadStateAtomDataReady){
		_state = ReadStateAtomHeader;
	}else if(_state == ReadStateNALUHeader){
		if(_reader.available < 4){
			return NO;
		}
		if(mp4_reader_next_nalu(_mp4)){
			_state = ReadStateNALUData;
		}else{
			log_debug(@"read mdat end");
			_state = ReadStateAtomHeader;
		}
	}else if(_state == ReadStateNALUData){
		if(_reader.available < _mp4->nalu->size){
			return NO;
		}
		_state = ReadStateNALUDataReady;
	}else if(_state == ReadStateNALUDataReady){
		_state = ReadStateNALUHeader;
	}
	return YES;
}

@end
