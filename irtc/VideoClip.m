//
//  VideoClip.m
//  irtc
//
//  Created by ideawu on 3/5/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "VideoClip.h"

@interface VideoClip(){
	NSData *_naluStartCode;
	double _nextFramePTS;
}
@property (readonly) int nextFrameIndex;
@property NSMutableArray *frames;
@end

@implementation VideoClip

- (id)init{
	self = [super init];
	_frames = [[NSMutableArray alloc] init];
	[self initStartCode];
	[self reset];
	return self;
}

- (double)duration{
	return _endTime - _startTime;
}

- (double)frameDuration{
	if(_frameCount <= 1){
		return 0;
	}
	return self.duration / (_frameCount - 1);
}

- (double)nextFramePTS{
	if(_nextFramePTS == 0){
		return _startTime;
	}else{
		return _nextFramePTS;
	}
}

- (void)reset{
	_startTime = -1;
	_endTime = -1;
	_frameCount = 0;
	_hasKeyFrame = NO;
	_nextFrameIndex = 0;
	_nextFramePTS = 0;
	[_frames removeAllObjects];
}

- (void)initStartCode{
	char codes[4];
	codes[0] = 0x00;
	codes[1] = 0x00;
	codes[2] = 0x00;
	codes[3] = 0x01;
	_naluStartCode = [NSData dataWithBytes:codes length:4];
}

- (NSString *)metastr{
	return [NSString stringWithFormat:[VideoClip metadataFormat],
			_startTime, _endTime, _frameCount];
}

+ (NSString *)metadataFormat{
	// %20.5f 只占用 20 宽度
	return @"v\n%.5f\n%.5f\n%d\n\n";
}

- (void)appendFrame:(NSData *)frame pts:(double)pts{
	unsigned char* pNal = (unsigned char*)[frame bytes];
	int type = pNal[4] & 0x1f;
	NSLog(@"add frame type: %d, pts: %f", type, pts);
	if (type == 5){
		_hasKeyFrame = YES;
		_frameCount ++;
	}else if(type == 1){
		_frameCount ++;
	}else if(type == 7){
		_sps = frame;
		return;
	}else if(type == 7){
		_pps = frame;
		return;
	}else{
		NSLog(@"unknown nal_type: %d", type);
		return;
	}
	
	if(_startTime == -1){
		_startTime = pts;
	}
	_startTime = MIN(_startTime, pts);
	_endTime = MAX(_endTime, pts);
	[_frames addObject:frame];
}

- (NSData *)nextFrame:(double *)pts{
	if(_nextFrameIndex >= _frames.count){
		return nil;
	}
	if(_nextFramePTS == 0){
		_nextFramePTS = _startTime;
	}
	NSData *frame = [_frames objectAtIndex:_nextFrameIndex];
	_nextFrameIndex ++;
	*pts = _nextFramePTS;
	
	uint8_t *pNal = (uint8_t*)[frame bytes];
	int idc = pNal[4] & 0x60;
	int type = pNal[4] & 0x1f;
	if (idc == 0 && type == 6) { // SEI
		//
	}else{
		if(_nextFrameIndex == _frames.count - 1){
			_nextFramePTS = _endTime;
		}else{
			_nextFramePTS += self.frameDuration;
		}
	}
	return frame;
}


// 1 sample buffer contains multiple NALUs(slices) in AVCC format
// http://stackoverflow.com/questions/28396622/extracting-h264-from-cmblockbuffer
// slice header has the 1-byte type, then one UE value,
// then the frame number.
// 8 bits NALU type
// 1 bit
// 1 bit, first mb in slice: 1 - frame begin

- (void)appendNALUWithFrame:(NSData *)frame toData:(NSMutableData *)data{
	[data appendData:_naluStartCode];
	UInt8 *p = (UInt8 *)frame.bytes;
	[data appendBytes:p + 4 length:frame.length - 4];
}

- (NSData *)stream{
	static UInt8 start_code[4] = {0, 0, 0, 1};

	NSMutableData *ret = [[NSMutableData alloc] init];
	[ret appendData:[[self metastr] dataUsingEncoding:NSUTF8StringEncoding]];

	for(NSData *frame in _frames){
		UInt8 *buf = (UInt8 *)frame.bytes;
		int size = (int)frame.length;
		int type = buf[4] & 0x1f;
		if(type == 5){ // IDR
			[ret appendBytes:&start_code length:4];
			[ret appendData:_sps];
			[ret appendBytes:&start_code length:4];
			[ret appendData:_pps];
		}
		while(size > 0){
			uint32_t len = (buf[0]<<24) + (buf[1]<<16) + (buf[2]<<8) + buf[3];
			if(len == 1){
				// 虽然要求 Annex-B, 但也兼容 AVCC
				[ret appendData:frame];
				break;
			}
			[ret appendBytes:&start_code length:4];
			[ret appendBytes:buf+4 length:len];
			buf += 4 + len;
			size -= 4 + len;
		}
	}
	return ret;
}

- (void)parseStream:(NSData *)stream{
	NSData *spr = [@"\n\n" dataUsingEncoding:NSUTF8StringEncoding];
	NSRange range = [stream rangeOfData:spr options:0 range:NSMakeRange(0, stream.length)];
	if(range.length == 0){
		return;
	}
	NSData *metadata = [stream subdataWithRange:NSMakeRange(0, range.location+range.length)];
	NSString *metastr = [[NSString alloc] initWithData:metadata encoding:NSUTF8StringEncoding];
	if(!metastr){
		log_debug(@"no metadata");
		return;
	}
	NSArray *ps = [metastr componentsSeparatedByString:@"\n"];
	if(ps.count < 4){
		log_debug(@"bad metadata");
		return;
	}
	double stime = [ps[1] doubleValue];
	double etime = [ps[2] doubleValue];
	//int frameCount = [ps[3] intValue];
	//NSLog(@"parsed stime: %.3f, etime: %.3f, duration: %.3f, frames: %d", stime, etime, (etime-stime), frameCount);

	UInt8 *buf = (UInt8 *)stream.bytes + metadata.length;
	size_t size = stream.length - metadata.length;
	uint32_t header = (buf[0]<<24) + (buf[1]<<16) + (buf[2]<<8) + buf[3];
	if(header == 1){
		log_debug(@"");
		// Annex-B
		NSData *data = [NSData dataWithBytesNoCopy:buf length:size];

		NSUInteger pos = 4;
		while(pos < data.length){
			size = data.length - pos;
			range = [data rangeOfData:_naluStartCode options:0 range:NSMakeRange(pos, size)];
			if(range.length == 0){
				range.location = data.length;
			}

			NSMutableData *ret = [[NSMutableData alloc] init];
			uint32_t len = (UInt32)range.location - (UInt32)pos;
			uint32_t bigendian_len = htonl(len);
			[ret appendBytes:&bigendian_len length:4];
			[ret appendBytes:buf + 4 length:len];
			NSLog(@"parsed frame: %d", (int)ret.length);
			[self appendFrame:ret pts:0];

			pos = range.location + range.length;
			buf += 4 + len;
			size -= 4 + len;
		}
	}else{
		// AVCC
		NSMutableData *ret = nil;
		while(size > 0){
			uint32_t len = (buf[0]<<24) + (buf[1]<<16) + (buf[2]<<8) + buf[3];
			UInt8 first_mb = buf[5] & 0x80;
			int type = buf[4] & 0x1f;
			if(first_mb == 0x80){
				if(ret){
					[self appendFrame:ret pts:0];
				}
				ret = [[NSMutableData alloc] init];
			}
			uint32_t bigendian_len = htonl(len);
			[ret appendBytes:&bigendian_len length:4];
			[ret appendBytes:buf+4 length:len];

			if(type == 7){
				_sps = ret;
				ret = [[NSMutableData alloc] init];
			}else if(type == 8){
				_pps = ret;
				ret = [[NSMutableData alloc] init];
			}

			buf += 4 + len;
			size -= 4 + len;
		}
		if(ret){
			[self appendFrame:ret pts:0];
		}
	}
	_startTime = stime;
	_endTime = etime;
}

- (void)findNALU:(NSData *)nalu{

}

@end
