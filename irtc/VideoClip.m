//
//  VideoClip.m
//  irtc
//
//  Created by ideawu on 3/5/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "VideoClip.h"

static UInt8 start_code[4] = {0, 0, 0, 1};

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
	_naluStartCode = [NSData dataWithBytes:start_code length:4];
}

- (void)appendFrame:(NSData *)frame pts:(double)pts{
	unsigned char* p = (unsigned char*)[frame bytes];
	int type = p[4] & 0x1f;
	//log_debug(@"add frame type: %d, pts: %f", type, pts);
	if (type == 5){
		_hasKeyFrame = YES;
		_frameCount ++;
	}else if(type == 1){
		_frameCount ++;
	}else if(type == 7){
		_sps = [frame subdataWithRange:NSMakeRange(4, frame.length - 4)];
		return;
	}else if(type == 8){
		_pps = [frame subdataWithRange:NSMakeRange(4, frame.length - 4)];
		return;
	}else{
		log_debug(@"unknown nal_type: %d", type);
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
	
	uint8_t *p = (uint8_t*)[frame bytes];
	int idc = p[4] & 0x60;
	int type = p[4] & 0x1f;
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

- (NSString *)metastr{
	return [NSString stringWithFormat:[VideoClip metadataFormat],
			_startTime, _endTime, _frameCount];
}

+ (NSString *)metadataFormat{
	// %20.5f 只占用 20 宽度
	return @"v\n%.5f\n%.5f\n%d\n\n";
}

- (NSData *)data{
	NSMutableData *ret = [[NSMutableData alloc] init];
	[ret appendData:[[self metastr] dataUsingEncoding:NSUTF8StringEncoding]];

	for(NSData *frame in _frames){
		UInt8 *buf = (UInt8 *)frame.bytes;
		int type = buf[4] & 0x1f;
		if(type == 5){ // IDR
			uint32_t bigendian_len;
			
			bigendian_len = htonl(_sps.length);
			[ret appendBytes:&bigendian_len length:4];
			[ret appendData:_sps];
			
			bigendian_len = htonl(_pps.length);
			[ret appendBytes:&bigendian_len length:4];
			[ret appendData:_pps];
		}
		[ret appendData:frame];
//		while(size > 0){
//			uint32_t len = (buf[0]<<24) + (buf[1]<<16) + (buf[2]<<8) + buf[3];
//			if(len == 1){
//				// 虽然要求 Annex-B, 但也兼容 AVCC
//				[ret appendData:frame];
//				break;
//			}
//			[ret appendBytes:start_code length:4];
//			[ret appendBytes:buf+4 length:len];
//			buf += 4 + len;
//			size -= 4 + len;
//		}
	}
	return ret;
}

// 1 sample buffer contains multiple NALUs(slices) in AVCC format
// http://stackoverflow.com/questions/28396622/extracting-h264-from-cmblockbuffer
// slice header has the 1-byte type, then one UE value,
// then the frame number.
// 8 bits NALU type
// 1 bit
// 1 bit, first mb in slice: 1 - frame begin

- (void)parseData:(NSData *)data{
	NSData *spr = [@"\n\n" dataUsingEncoding:NSUTF8StringEncoding];
	NSRange range = [data rangeOfData:spr options:0 range:NSMakeRange(0, data.length)];
	if(range.length == 0){
		return;
	}
	NSData *metadata = [data subdataWithRange:NSMakeRange(0, range.location+range.length)];
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
	//log_debug(@"parsed stime: %.3f, etime: %.3f, duration: %.3f, frames: %d", stime, etime, (etime-stime), frameCount);

	UInt8 *buf = (UInt8 *)data.bytes + metadata.length;
	size_t size = data.length - metadata.length;
	
	// AVCC
	NSMutableData *frame = [[NSMutableData alloc] init];
	while(size > 0){
		uint32_t len = (buf[0]<<24) + (buf[1]<<16) + (buf[2]<<8) + buf[3];
		UInt8 first_mb = buf[5] & 0x80;
		int type = buf[4] & 0x1f;
		if(first_mb == 0x80 || type == 7 || type == 8){ // the first slice/nalu of a frame
			if(frame.length > 0){
				[self appendFrame:frame pts:0];
				frame = [[NSMutableData alloc] init];
			}
		}
		[frame appendBytes:buf length:4 + len];
		// in case SPS is not the first frame in stream
		if(type == 7 || type == 8){
			[self appendFrame:frame pts:0];
			frame = [[NSMutableData alloc] init];
		}

		buf += 4 + len;
		size -= 4 + len;
	}
	if(frame.length > 0){
		[self appendFrame:frame pts:0];
	}

	_startTime = stime;
	_endTime = etime;
}

@end
