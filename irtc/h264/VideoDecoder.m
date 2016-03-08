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
	void (^_callback)(CVImageBufferRef imageBuffer);
}
@property (nonatomic, assign) VTDecompressionSessionRef decodeSession;
@property (nonatomic, assign) CMVideoFormatDescriptionRef formatDesc;
@end


@implementation VideoDecoder

- (id)init{
	self = [super init];
	_callback = NULL;
	_decodeSession = NULL;
	_formatDesc = NULL;
	return self;
}

- (BOOL)readyForFrame{
	return _decodeSession != NULL;
}

- (void)setCallback:(void (^)(CVImageBufferRef imageBuffer))callback{
	_callback = callback;
}

- (void)setSps:(NSData *)sps pps:(NSData *)pps{
	if(_formatDesc){
		CFRelease(_formatDesc);
	}
	// no start code
	uint8_t*  parameterSetPointers[2] = {(uint8_t*)sps.bytes, (uint8_t*)pps.bytes};
	size_t parameterSetSizes[2] = {sps.length, sps.length};
	
	OSStatus status;
	status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2,
																 (const uint8_t *const*)parameterSetPointers,
																 parameterSetSizes, 4,
																 &_formatDesc);
	if(status != noErr) NSLog(@"Create Format Description ERROR: %d", (int)status);
	
	if(_decodeSession){
		VTDecompressionSessionInvalidate(_decodeSession);
		CFRelease(_decodeSession);
	}
	[self createDecompessSession];
}

- (void)createDecompessSession{
	VTDecompressionOutputCallbackRecord callBackRecord;
	callBackRecord.decompressionOutputCallback = decompressionSessionDecodeFrameCallback;
	callBackRecord.decompressionOutputRefCon = (__bridge void *)self;

	NSDictionary *decoderParameters = @{
										(id)kVTDecompressionPropertyKey_RealTime: @(YES),
										};
	
	// you can set some desired attributes for the destination pixel buffer.  I didn't use this but you may
	// if you need to set some attributes, be sure to uncomment the dictionary in VTDecompressionSessionCreate
#if !TARGET_OS_MAC
	NSDictionary *pixelBufferAttrs = @{
									   (id)kCVPixelBufferOpenGLESCompatibilityKey: @(YES),
									   };
#else
	NSDictionary *pixelBufferAttrs = @{
									   (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
									   //(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
									   };
#endif
	OSStatus status =  VTDecompressionSessionCreate(NULL, _formatDesc,
													(__bridge CFDictionaryRef)(decoderParameters),
													(__bridge CFDictionaryRef)(pixelBufferAttrs),
													&callBackRecord, &_decodeSession);
	if(status != noErr) NSLog(@"\t\t VTD ERROR type: %d", (int)status);
}

void decompressionSessionDecodeFrameCallback(void *decompressionOutputRefCon,
											 void *sourceFrameRefCon,
											 OSStatus status,
											 VTDecodeInfoFlags infoFlags,
											 CVImageBufferRef imageBuffer,
											 CMTime presentationTimeStamp,
											 CMTime presentationDuration){
	if(status != noErr){
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		NSLog(@"Decompressed error: %@", error);
		return;
	}
	//NSLog(@"%f %f", CMTimeGetSeconds(presentationTimeStamp), CMTimeGetSeconds(presentationDuration));
	VideoDecoder *decoder = (__bridge VideoDecoder *)decompressionOutputRefCon;
	[decoder callbackImageBuffer:imageBuffer];
}

- (void)callbackImageBuffer:(CVImageBufferRef)imageBuffer{
	if(_callback){
		_callback(imageBuffer);
	}
}

- (void)appendFrame:(NSData *)frame{
	uint8_t *pNal = (uint8_t*)[frame bytes];
	//int nal_ref_idc = pNal[0] & 0x60;
	int nal_type = pNal[0] & 0x1f;
//	NSLog(@"NALU Type \"%d\"", nal_type);
	
	CMSampleBufferRef sampleBuffer = NULL;
	CMBlockBufferRef blockBuffer = NULL;
	
	// 如何处理 SEI?
	
	if(nal_type == 5 || nal_type == 1){
		uint8_t *data = NULL;
		size_t nalu_len = frame.length + 4;
		size_t data_len = frame.length;
		data = malloc(nalu_len);
		memcpy(data + 4, frame.bytes, data_len);
		
		// replace the start code header on this NALU with its size.
		// AVCC format requires that you do this.
		// htonl converts the unsigned int from host to network byte order
		uint32_t len = htonl(data_len);
		memcpy(data, &len, 4);
		
		OSStatus status;
		// create a block buffer from the IDR NALU
		status = CMBlockBufferCreateWithMemoryBlock(NULL, data,  // memoryBlock to hold buffered data
													nalu_len,  // block length of the mem block in bytes.
													kCFAllocatorNull, NULL,
													0, // offsetToData
													nalu_len, // dataLength of relevant bytes, starting at offsetToData
													0, &blockBuffer);
		if(status == noErr){
			//NSLog(@"blockBuffer: %d", (int)CFGetRetainCount(blockBuffer));
			const size_t sampleSize = nalu_len;
			status = CMSampleBufferCreate(kCFAllocatorDefault,
										  blockBuffer, true, NULL, NULL,
										  _formatDesc,
										  1, // num samples
										  0, NULL,
										  1, &sampleSize,
										  &sampleBuffer);
			//NSLog(@"blockBuffer: %d", (int)CFGetRetainCount(blockBuffer));
		}
		
		//free(data); //由 blockBuffer 释放
		// 在这里可以放心地 release blockBuffer, 而且必须 release, 因为 sampleBuffer 已经 retain 了
		CFRelease(blockBuffer);
		
		if(status == noErr){
			VTDecodeFrameFlags flags = kVTDecodeFrame_EnableAsynchronousDecompression;
			VTDecodeInfoFlags flagOut;
			NSDate* currentTime = [NSDate date];
			//NSLog(@"sampleBuffer: %d", (int)CFGetRetainCount(sampleBuffer));
			VTDecompressionSessionDecodeFrame(_decodeSession, sampleBuffer, flags,
											  (void*)CFBridgingRetain(currentTime), &flagOut);
			CFRelease(sampleBuffer);
			
			//NSLog(@"sampleBuffer: %d", (int)CFGetRetainCount(sampleBuffer));
			// set some values of the sample buffer's attachments
//			CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
//			CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
//			CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
			// either send the samplebuffer to a VTDecompressionSession or to an AVSampleBufferDisplayLayer
		}
	}
}

@end
