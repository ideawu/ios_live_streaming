//
//  VideoDecoder.m
//  irtc
//
//  Created by ideawu on 3/7/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "VideoDecoder.h"
#import <VideoToolbox/VideoToolbox.h>

@interface VideoDecoder(){
	void (^_callback)(CVPixelBufferRef pixelBuffer, double pts, double duration);
}
@property (nonatomic, assign) VTDecompressionSessionRef session;
@property (nonatomic, assign) CMVideoFormatDescriptionRef formatDesc;
@end


@implementation VideoDecoder

- (id)init{
	self = [super init];
	_callback = NULL;
	_session = NULL;
	_formatDesc = NULL;
	return self;
}

- (void)dealloc{
	[self shutdown];
}

- (void)shutdown{
	if(_session){
		VTDecompressionSessionInvalidate(_session);
		CFRelease(_session);
		_session = NULL;
	}
	if(_formatDesc){
		CFRelease(_formatDesc);
		_formatDesc = NULL;
	}
}

- (BOOL)isReadyForFrame{
	return _session != NULL;
}

- (void)start:(void (^)(CVPixelBufferRef pixelBuffer, double pts, double duration))callback{
	_callback = callback;
}

- (void)setSps:(NSData *)sps pps:(NSData *)pps{
	if(_formatDesc){
		CFRelease(_formatDesc);
	}
	// no start code
	uint8_t*  parameterSetPointers[2] = {(uint8_t*)sps.bytes, (uint8_t*)pps.bytes};
	size_t parameterSetSizes[2] = {sps.length, sps.length};
	
	OSStatus err;
	err = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2,
																 (const uint8_t *const*)parameterSetPointers,
																 parameterSetSizes, 4,
																 &_formatDesc);
	if(err != noErr) NSLog(@"Create Format Description ERROR: %d", (int)err);
	
	[self createSession];
}

- (void)createSession{
	if(_session){
		[self shutdown];
	}

	VTDecompressionOutputCallbackRecord callBackRecord;
	callBackRecord.decompressionOutputCallback = decompressionSessionDecodeFrameCallback;
	callBackRecord.decompressionOutputRefCon = (__bridge void *)self;

	// you can set some desired attributes for the destination pixel buffer.  I didn't use this but you may
	// if you need to set some attributes, be sure to uncomment the dictionary in VTDecompressionSessionCreate
#if !TARGET_OS_MAC
	NSDictionary *decoderParameters = @{
										(id)kVTDecompressionPropertyKey_RealTime: @(YES),
										};
	NSDictionary *pixelBufferAttrs = @{
									   (id)kCVPixelBufferOpenGLESCompatibilityKey: @(YES),
									   };
#else
	NSDictionary *decoderParameters = nil;
	NSDictionary *pixelBufferAttrs = @{
									   (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
									   //(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
									   };
#endif
	OSStatus status =  VTDecompressionSessionCreate(NULL, _formatDesc,
													(__bridge CFDictionaryRef)(decoderParameters),
													(__bridge CFDictionaryRef)(pixelBufferAttrs),
													&callBackRecord, &_session);
	if(status != noErr) NSLog(@"\t\t VTD ERROR type: %d", (int)status);
	log_debug(@"decode session created");
}

// VTDecompressionOutputCallback
static void decompressionSessionDecodeFrameCallback(void *decompressionOutputRefCon,
													void *sourceFrameRefCon,
													OSStatus status,
													VTDecodeInfoFlags infoFlags,
													CVImageBufferRef imageBuffer,
													CMTime pts,
													CMTime duration){
	if(status != noErr){
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		log_debug(@"Decompressed error: %@", error);
		return;
	}
//	NSLog(@"%f %f", CMTimeGetSeconds(pts), CMTimeGetSeconds(duration));
	VideoDecoder *decoder = (__bridge VideoDecoder *)decompressionOutputRefCon;
	[decoder callbackImageBuffer:imageBuffer pts:CMTimeGetSeconds(pts) duration:CMTimeGetSeconds(duration)];
}

- (void)callbackImageBuffer:(CVImageBufferRef)imageBuffer pts:(double)pts duration:(double)duration{
	if(_callback){
		_callback(imageBuffer, pts, duration);
	}
}

- (void)decode:(NSData *)frame{
	return [self decode:frame pts:0 duration:0];
}

- (void)decode:(NSData *)frame pts:(double)pts{
	return [self decode:frame pts:pts duration:0];
}

- (void)decode:(NSData *)frame pts:(double)pts duration:(double)duration{
	// BOOL needNewSession = ( VTDecompressionSessionCanAcceptFormatDescription(session, formatDesc2 ) == false);
	CMSampleBufferRef sampleBuffer = [self createSampleBufferWithFrame:frame pts:pts duration:duration];
	if(sampleBuffer){
		// 不能异步, 否则会乱序
		//VTDecodeFrameFlags flags = kVTDecodeFrame_EnableAsynchronousDecompression;
		VTDecodeFrameFlags flags = 0;
		VTDecodeInfoFlags flagOut;
		//NSLog(@"sampleBuffer: %d", (int)CFGetRetainCount(sampleBuffer));
		// decode 接受的1帧, 可以分隔多个NALU, AVCC 格式
		VTDecompressionSessionDecodeFrame(_session, sampleBuffer, flags, NULL, &flagOut);
		CFRelease(sampleBuffer);
	}
}

- (CMSampleBufferRef)createSampleBufferWithFrame:(NSData *)frame pts:(double)pts duration:(double)duration{
	CMSampleBufferRef sampleBuffer = NULL;
	CMBlockBufferRef blockBuffer = NULL;
	size_t length = frame.length;
	OSStatus err;
	err = CMBlockBufferCreateWithMemoryBlock(NULL,
											 NULL,
											 length,
											 kCFAllocatorDefault,
											 NULL,
											 0,
											 length,
											 kCMBlockBufferAssureMemoryNowFlag,
											 &blockBuffer);
	if (err != 0) {
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		log_debug(@"error: %@", error);
	}else{
		err = CMBlockBufferReplaceDataBytes(frame.bytes, blockBuffer, 0, length);
		// 兼容 Annex-B 封装
		UInt8 *p = (UInt8 *)frame.bytes;
		if(p[0] == 0 && p[1] == 0 && p[2] == 0 && p[3] == 1){
			UInt32 len = ntohl(length - 4);
			err = CMBlockBufferReplaceDataBytes(&len, blockBuffer, 0, 4);
		}
	}
	if (err != 0) {
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		log_debug(@"error: %@", error);
	}else{
		CMSampleTimingInfo time;
		time.presentationTimeStamp = CMTimeMakeWithSeconds(pts, 60000);
		time.duration = CMTimeMakeWithSeconds(duration, 60000);
		err = CMSampleBufferCreate(kCFAllocatorDefault,
								   blockBuffer,
								   true, NULL, NULL,
								   _formatDesc,
								   1, // num samples
								   1, &time,
								   1, &length,
								   &sampleBuffer);
	}
	if (err != 0) {
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		log_debug(@"error: %@", error);
	}

	if(blockBuffer){
		CFRelease(blockBuffer);
	}

	return sampleBuffer;
}


//- (void)decode:(NSData *)frame pts:(double)pts{
//	uint8_t *pNal = (uint8_t*)[frame bytes];
//	//int nal_ref_idc = pNal[0] & 0x60;
//	int nal_type = pNal[0] & 0x1f;
////	NSLog(@"NALU Type \"%d\"", nal_type);
//
//	CMSampleBufferRef sampleBuffer = NULL;
//	CMBlockBufferRef blockBuffer = NULL;
//
//	// 如何处理 SEI?
//
//	if(1 || nal_type == 5 || nal_type == 1){
//		uint8_t *data = NULL;
//		size_t nalu_len = frame.length;
//		data = malloc(nalu_len);
//		memcpy(data, frame.bytes, nalu_len);
//		
//		// replace the start code header on this NALU with its size.
//		// AVCC format requires that you do this.
//		// htonl converts the unsigned int from host to network byte order
//		size_t data_len = frame.length - 4;
//		uint32_t len = htonl(data_len);
//		memcpy(data, &len, 4);
//		
//		OSStatus status;
//
//		status = CMBlockBufferCreateWithMemoryBlock(NULL, data,  // memoryBlock to hold buffered data
//													nalu_len,  // block length of the mem block in bytes.
//													kCFAllocatorNull, NULL,
//													0, // offsetToData
//													nalu_len, // dataLength of relevant bytes, starting at offsetToData
//													0, &blockBuffer);
//		if(status == noErr){
//			//NSLog(@"blockBuffer: %d", (int)CFGetRetainCount(blockBuffer));
//			const size_t sampleSize = nalu_len;
//			status = CMSampleBufferCreate(kCFAllocatorDefault,
//										  blockBuffer, true, NULL, NULL,
//										  _formatDesc,
//										  1, // num samples
//										  0, NULL,
//										  1, &sampleSize,
//										  &sampleBuffer);
//			//NSLog(@"blockBuffer: %d", (int)CFGetRetainCount(blockBuffer));
//		}
//		
//		//free(data); //由 blockBuffer 释放
//		// 在这里可以放心地 release blockBuffer, 而且必须 release, 因为 sampleBuffer 已经 retain 了
//		CFRelease(blockBuffer);
//		
//		if(status == noErr){
//			// 不能异步, 否则会乱序
//			//VTDecodeFrameFlags flags = kVTDecodeFrame_EnableAsynchronousDecompression;
//			VTDecodeFrameFlags flags = 0;
//			VTDecodeInfoFlags flagOut;
//			NSNumber *framePTS = @(pts);
//			//NSLog(@"sampleBuffer: %d", (int)CFGetRetainCount(sampleBuffer));
//			VTDecompressionSessionDecodeFrame(_session, sampleBuffer, flags,
//											  (void*)CFBridgingRetain(framePTS), &flagOut);
//			CFRelease(sampleBuffer);
//			
//			//NSLog(@"sampleBuffer: %d", (int)CFGetRetainCount(sampleBuffer));
//			// set some values of the sample buffer's attachments
////			CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
////			CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
////			CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
//			// either send the samplebuffer to a VTDecompressionSession or to an AVSampleBufferDisplayLayer
//		}
//	}
//}

@end
