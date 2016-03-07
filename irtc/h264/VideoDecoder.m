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
}
//@property (nonatomic, assign) VTDecompressionSessionRef decodeSession;
@property (nonatomic, assign) CMVideoFormatDescriptionRef formatDesc;
@end


@implementation VideoDecoder

- (id)init{
	self = [super init];
	return self;
}

- (void)setSps:(NSData *)sps pps:(NSData *)pps{
	// no start code
	uint8_t*  parameterSetPointers[2] = {(uint8_t*)sps.bytes, (uint8_t*)pps.bytes};
	size_t parameterSetSizes[2] = {sps.length, sps.length};
	
	OSStatus status;
	status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2,
																 (const uint8_t *const*)parameterSetPointers,
																 parameterSetSizes, 4,
																 &_formatDesc);
	if(status != noErr) NSLog(@"Create Format Description ERROR: %d", (int)status);
}

// TODO: 改用 VTDecompressionSessionRef, 处理 reordering
// 调用者负责释放内存
- (CMSampleBufferRef)processFrame:(NSData *)frame{
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
			const size_t sampleSize = nalu_len;
			status = CMSampleBufferCreate(kCFAllocatorDefault,
										  blockBuffer, true, NULL, NULL,
										  _formatDesc,
										  1, // num samples
										  0, NULL,
										  1, &sampleSize,
										  &sampleBuffer);
			//			NSLog(@"\t\t SampleBufferCreate: \t %@", (status == noErr) ? @"successful!" : @"failed...");
		}
		
		//free(data); //由 blockBuffer 释放
		// 在这里可以放心地 release blockBuffer, 而且必须 release, 因为 sampleBuffer 已经 retain 了
		CFRelease(blockBuffer);
		
		if(status == noErr){
			// set some values of the sample buffer's attachments
			CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
			CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
			CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
			// either send the samplebuffer to a VTDecompressionSession or to an AVSampleBufferDisplayLayer
			return sampleBuffer;
		}
	}
	return NULL;
}

//- (void)receivedRawVideoFrame:(uint8_t *)frame withSize:(uint32_t)frameSize isIFrame:(int)isIFrame{
//	OSStatus status;
//	CMSampleBufferRef sampleBuffer = NULL;
//	CMBlockBufferRef blockBuffer = NULL;
//
//	int nalu_type = (frame[startCodeIndex + 4] & 0x1F);
//	NSLog(@"~~~~~~~ Received NALU Type \"%@\" ~~~~~~~~", naluTypesStrings[nalu_type]);
//	// type 8 is the PPS parameter NALU
//	if(nalu_type == 8){
//		// find where the NALU after this one starts so we know how long the PPS parameter is
//		for (int i = _spsSize + 4; i < _spsSize + 30; i++){
//			if (frame[i] == 0x00 && frame[i+1] == 0x00 && frame[i+2] == 0x00 && frame[i+3] == 0x01){
//				thirdStartCodeIndex = i;
//				_ppsSize = thirdStartCodeIndex - _spsSize;
//				break;
//			}
//		}
//
//
//		// See if decomp session can convert from previous format description
//		// to the new one, if not we need to remake the decomp session.
//		// This snippet was not necessary for my applications but it could be for yours
//		/*BOOL needNewDecompSession = (VTDecompressionSessionCanAcceptFormatDescription(_decompressionSession, _formatDesc) == NO);
//		 if(needNewDecompSession)
//		 {
//		 [self createDecompSession];
//		 }*/
//
//		// now lets handle the IDR frame that (should) come after the parameter sets
//		// I say "should" because that's how I expect my H264 stream to work, YMMV
//		nalu_type = (frame[thirdStartCodeIndex + 4] & 0x1F);
//		NSLog(@"~~~~~~~ Received NALU Type \"%@\" ~~~~~~~~", naluTypesStrings[nalu_type]);
//	}
//
//	// create our VTDecompressionSession.  This isnt neccessary if you choose to use AVSampleBufferDisplayLayer
//	if((status == noErr) && (_decompressionSession == NULL)){
//		[self createDecompSession];
//	}
//}
//
//-(void) createDecompSession
//{
//	// make sure to destroy the old VTD session
//	_decompressionSession = NULL;
//	VTDecompressionOutputCallbackRecord callBackRecord;
//	callBackRecord.decompressionOutputCallback = decompressionSessionDecodeFrameCallback;
//
//	// this is necessary if you need to make calls to Objective C "self" from within in the callback method.
//	callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
//
//	// you can set some desired attributes for the destination pixel buffer.  I didn't use this but you may
//	// if you need to set some attributes, be sure to uncomment the dictionary in VTDecompressionSessionCreate
//	NSDictionary *destinationImageBufferAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
//													  [NSNumber numberWithBool:YES],
//													  (id)kCVPixelBufferOpenGLESCompatibilityKey,
//													  nil];
//
//	OSStatus status =  VTDecompressionSessionCreate(NULL, _formatDesc, NULL,
//													NULL, // (__bridge CFDictionaryRef)(destinationImageBufferAttributes)
//													&callBackRecord, &_decompressionSession);
//	NSLog(@"Video Decompression Session Create: \t %@", (status == noErr) ? @"successful!" : @"failed...");
//	if(status != noErr) NSLog(@"\t\t VTD ERROR type: %d", (int)status);
//}
//
//
//
//void decompressionSessionDecodeFrameCallback(void *decompressionOutputRefCon,
//											 void *sourceFrameRefCon,
//											 OSStatus status,
//											 VTDecodeInfoFlags infoFlags,
//											 CVImageBufferRef imageBuffer,
//											 CMTime presentationTimeStamp,
//											 CMTime presentationDuration)
//{
//	THISCLASSNAME *streamManager = (__bridge THISCLASSNAME *)decompressionOutputRefCon;
//
//	if (status != noErr)
//	{
//		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
//		NSLog(@"Decompressed error: %@", error);
//	}
//	else
//	{
//		NSLog(@"Decompressed sucessfully");
//
//		// do something with your resulting CVImageBufferRef that is your decompressed frame
//		[streamManager displayDecodedFrame:imageBuffer];
//	}
//}
//
//- (void) render:(CMSampleBufferRef)sampleBuffer{
//	VTDecodeFrameFlags flags = kVTDecodeFrame_EnableAsynchronousDecompression;
//	VTDecodeInfoFlags flagOut;
//	NSDate* currentTime = [NSDate date];
//	VTDecompressionSessionDecodeFrame(_decompressionSession, sampleBuffer, flags,
//									  (void*)CFBridgingRetain(currentTime), &flagOut);
//
//	CFRelease(sampleBuffer);
//	// if you're using AVSampleBufferDisplayLayer, you only need to use this line of code
//	// [videoLayer enqueueSampleBuffer:sampleBuffer];
//}

@end
