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
}
@end

@implementation VideoClip

+ (VideoClip *)clipFromData:(NSData *)data{
	VideoClip *ret = [[VideoClip alloc] init];
	[ret parseData:data];
	return ret;
}

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

- (void)reset{
	_startTime = -1;
	_endTime = -1;
	_frameCount = 0;
	_hasIFrame = NO;
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

- (void)appendNALUWithFrame:(NSData *)frame toData:(NSMutableData *)data{
	[data appendData:_naluStartCode];
	[data appendData:frame];
}

- (void)appendFrame:(NSData *)frame pts:(double)pts{
	//NSLog(@"append frame %d", (int)frame.length);
	if(_startTime == -1){
		_startTime = pts;
	}
	_endTime = pts;
	[_frames addObject:frame];
	
	unsigned char* pNal = (unsigned char*)[frame bytes];
	int nal_type = pNal[0] & 0x1f;
	if (nal_type == 5){
		_hasIFrame = YES;
		_frameCount ++;
	}else if(nal_type == 1){
		_frameCount ++;
	}
}

- (NSData *)data{
	NSData *_sei = nil;
	NSMutableData *ret = [[NSMutableData alloc] init];
	
	[ret appendData:[[self metastr] dataUsingEncoding:NSUTF8StringEncoding]];
	
	for (NSData *frame in _frames) {
		uint8_t *pNal = (uint8_t*)[frame bytes];
		int nal_ref_idc = pNal[0] & 0x60;
		int nal_type = pNal[0] & 0x1f;
		if (nal_ref_idc == 0 && nal_type == 6) { // SEI
			_sei = frame;
		} else if (nal_type == 5) { // I Frame
			[self appendNALUWithFrame:_sps toData:ret];
			[self appendNALUWithFrame:_pps toData:ret];
			if (_sei) {
				[self appendNALUWithFrame:_sei toData:ret];
				_sei = nil;
			}
			[self appendNALUWithFrame:frame toData:ret];
		} else {
			[self appendNALUWithFrame:frame toData:ret];
		}
	}
	return ret;
}

- (void)parseData:(NSData *)data{
	NSData *spr = [@"\n\n" dataUsingEncoding:NSUTF8StringEncoding];
	NSRange range = [data rangeOfData:spr options:0 range:NSMakeRange(0, data.length)];
	if(range.length == 0){
		return;
	}
	NSData *metadata = [data subdataWithRange:NSMakeRange(0, range.location)];
	NSString *metastr = [[NSString alloc] initWithData:metadata encoding:NSUTF8StringEncoding];
	if(!metastr){
		return;
	}
	NSArray *ps = [metastr componentsSeparatedByString:@"\n"];
	if(ps.count < 4){
		return;
	}
	double stime = [ps[1] doubleValue];
	double etime = [ps[2] doubleValue];
	int frameCount = [ps[3] intValue];
	NSLog(@"parsed stime: %.3f, etime: %.3f, frames: %d", stime, etime, frameCount);
	
	NSUInteger pos = range.location + range.length;
	NSUInteger len = data.length - pos;
	range = [data rangeOfData:_naluStartCode options:0 range:NSMakeRange(pos, len)];
	if(range.length == 0){
		NSLog(@"bad payload");
		return;
	}
	pos = range.location + range.length;
	double pts = stime;
	double frameDuration = (etime - stime) / frameCount;
	while(pos < data.length){
		len = data.length - pos;
		range = [data rangeOfData:_naluStartCode options:0 range:NSMakeRange(pos, len)];
		if(range.length == 0){
			range.location = data.length;
		}
		
		NSData *frame = [data subdataWithRange:NSMakeRange(pos, range.location - pos)];
		//NSLog(@"parsed frame: %d", (int)frame.length);
		
		uint8_t *pNal = (uint8_t*)[frame bytes];
		int nal_ref_idc = pNal[0] & 0x60;
		int nal_type = pNal[0] & 0x1f;
		if(nal_type == 7){
			_sps = frame;
		}else if(nal_type == 8){
			_pps = frame;
		}else{
			if(range.location == data.length){
				pts = etime;
			}
			//NSLog(@"pts: %f, type: %d", pts, nal_type);
			[self appendFrame:frame pts:pts];
			if (nal_ref_idc == 0 && nal_type == 6) { // SEI
				//
			}else{
				pts += frameDuration;
			}
		}
		
		pos = range.location + range.length;
	}
}


@end