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

#define MAX_FILE_COUNT     3
#define MAX_SWAP_FILE_SIZE (20 * 1024 * 1024)

@interface MP4FileVideoEncoder(){
	MP4FileWriter *_headerWriter;
	MP4FileWriter *_writer;
	MP4FileReader *_reader;
	
	void (^_callback)(NSData *frame, double pts, double duration);

	int _recordSeq;
	BOOL _swapping;
	NSMutableArray *_times;
	NSMutableData *_frame;

	dispatch_queue_t _readQueue;
}
@end


@implementation MP4FileVideoEncoder

- (id)init{
	self = [super init];
	_width = 480;
	_height = 640;
	_times = [[NSMutableArray alloc] init];
	_frame = [[NSMutableData alloc] init];
	_swapping = NO;
	_readQueue = dispatch_queue_create("MP4FileVideoEncoder", DISPATCH_QUEUE_SERIAL);
	return self;
}

- (void)dealloc{
	[self shutdown];
}

- (void)start:(void (^)(NSData *frame, double pts, double duration))callback{
	_callback = callback;
}

- (void)shutdown{
	dispatch_async(_readQueue, ^{
		if(_writer){
			MP4FileWriter *old = _writer;
			[old finishWithCompletionHandler:^{
				log_debug(@"finish completion");
				dispatch_async(_readQueue, ^{
					[self finishParse];
					id just_for_retain = old;
					just_for_retain = nil;
				});
			}];
		}
	});
}

- (NSString *)nextFilename{
	NSString *name = [NSString stringWithFormat:@"m%03d.mp4", _recordSeq];
	if(++_recordSeq >= MAX_FILE_COUNT){
		_recordSeq = 0;
	}
	return [NSTemporaryDirectory() stringByAppendingPathComponent:name];
}

- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	CFRetain(sampleBuffer);
	dispatch_async(_readQueue, ^{
		[self encodeSampleBuffer2:sampleBuffer];
		CFRelease(sampleBuffer);
	});
}

- (void)encodeSampleBuffer2:(CMSampleBufferRef)sampleBuffer{
	LOG_FIRST_RUN();
	__weak typeof(self) me = self;
	
	double pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
	double duration = CMTimeGetSeconds(CMSampleBufferGetDuration(sampleBuffer));
	NSArray *arr = @[@(pts), @(duration)];

	[_times addObject:arr];

//	CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
//	log_debug(@"width: %d, height: %d, %d bytes",
//			  (int)CVPixelBufferGetWidth(imageBuffer),
//			  (int)CVPixelBufferGetHeight(imageBuffer),
//			  (int)CVPixelBufferGetDataSize(imageBuffer)
//			  );

	if(!_sps && !_headerWriter){
		NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"params.mp4"];
		_headerWriter = [MP4FileWriter videoForPath:path Height:_height andWidth:_width bitrate:0];
		if([_headerWriter encodeSampleBuffer:sampleBuffer]){
			[_headerWriter finishWithCompletionHandler:^{
				[me parseHeaderFile];
			}];
		}else{
			log_error(@"write header writer failed");
		}
	}

	if(!_writer){
		NSString *path = [self nextFilename];
		_writer = [MP4FileWriter videoForPath:path Height:_height andWidth:_width bitrate:0];
	}
	// 实验得知, AVFoundation 要写至少3个frame之后, 才flush到硬盘,
	// 之后每写一个frame就flush一次. 这3个frame导致的延时在 200ms 左右.
	[_writer encodeSampleBuffer:sampleBuffer];

	if(!_swapping){
		if(_sps){
			[self onFileUpdate];
		}

		if(_reader.file.total > MAX_SWAP_FILE_SIZE){
			log_debug(@"swapping...");
			_swapping = YES;
			
			MP4FileWriter *old = _writer;
			[old finishWithCompletionHandler:^{
				dispatch_async(_readQueue, ^{
					[me swapDone];
					// 注意! 如果不在这里引用 old, 那么在 finishWithCompletionHandler() 执行完毕后和 callback 之前,
					// old 会被自动释放!
					id just_for_retain = old;
					just_for_retain = nil;
				});
			}];
			_writer = nil;
		}
	}
}

- (void)swapDone{
	log_debug(@"finishing swapping..");
	[self finishParse];
	log_debug(@"swapping done.");
	_swapping = NO;
	_reader = NULL;
	
	if(_writer){
		[self onFileUpdate];
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
		LOG_FIRST_RUN();

		uint8_t *p = (uint8_t*)[nalu bytes];
		int type = p[4] & 0x1f;
		if(type == 6){ // ignore SEI
			continue;
		}
		int first_mb = p[5] & 0x80;
//		int idc = p[4] & 0x60;
//		log_debug(@"type: %d, idc: %2d, first_mb: %3d, %6d bytes", type, idc, first_mb, (int)nalu.length);

		if(first_mb){
			if(_frame.length > 0){
				[_frame appendData:nalu];
				[self onFrameReady:_frame];

				_frame = [[NSMutableData alloc] init];
			}else{
				[self onFrameReady:nalu];
			}
		}else{
			[_frame appendData:nalu];
			continue;
		}

		// TODO: frame reordering
	}
}

- (void)onFrameReady:(NSData *)frame{
	double pts = 0;
	double duration = 0;
	if(_times.count > 0){
		NSArray *arr = [_times firstObject];
		[_times removeObjectAtIndex:0];
		pts = [arr[0] doubleValue];
		duration = [arr[1] doubleValue];
	}else{
		log_error(@"drop nalu without timestamp");
	}

	if(_callback){
		_callback(frame, pts, duration);
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
	//NSLog(@"sps: %@, pps: %@", _sps, _pps);
	_headerWriter = nil;
}

@end
