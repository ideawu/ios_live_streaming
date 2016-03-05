//
//  VideoDecoder.m
//  irtc
//
//  Created by ideawu on 3/5/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "VideoDecoder.h"
#import <AVFoundation/AVFoundation.h>

// VTErrors.h

@interface VideoDecoder(){
}
@property (nonatomic, assign) CMVideoFormatDescriptionRef formatDesc;
@property (nonatomic, assign) VTDecompressionSessionRef decompressionSession;
@property (nonatomic, assign) int spsSize;
@property (nonatomic, assign) int ppsSize;
@end

NSString * const naluTypesStrings[] =
{
	@"0: Unspecified (non-VCL)",
	@"1: Coded slice of a non-IDR picture (VCL)",    // P frame
	@"2: Coded slice data partition A (VCL)",
	@"3: Coded slice data partition B (VCL)",
	@"4: Coded slice data partition C (VCL)",
	@"5: Coded slice of an IDR picture (VCL)",      // I frame
	@"6: Supplemental enhancement information (SEI) (non-VCL)",
	@"7: Sequence parameter set (non-VCL)",         // SPS parameter
	@"8: Picture parameter set (non-VCL)",          // PPS parameter
	@"9: Access unit delimiter (non-VCL)",
	@"10: End of sequence (non-VCL)",
	@"11: End of stream (non-VCL)",
	@"12: Filler data (non-VCL)",
	@"13: Sequence parameter set extension (non-VCL)",
	@"14: Prefix NAL unit (non-VCL)",
	@"15: Subset sequence parameter set (non-VCL)",
	@"16: Reserved (non-VCL)",
	@"17: Reserved (non-VCL)",
	@"18: Reserved (non-VCL)",
	@"19: Coded slice of an auxiliary coded picture without partitioning (non-VCL)",
	@"20: Coded slice extension (non-VCL)",
	@"21: Coded slice extension for depth view components (non-VCL)",
	@"22: Reserved (non-VCL)",
	@"23: Reserved (non-VCL)",
	@"24: STAP-A Single-time aggregation packet (non-VCL)",
	@"25: STAP-B Single-time aggregation packet (non-VCL)",
	@"26: MTAP16 Multi-time aggregation packet (non-VCL)",
	@"27: MTAP24 Multi-time aggregation packet (non-VCL)",
	@"28: FU-A Fragmentation unit (non-VCL)",
	@"29: FU-B Fragmentation unit (non-VCL)",
	@"30: Unspecified (non-VCL)",
	@"31: Unspecified (non-VCL)",
};

@implementation VideoDecoder

- (void)setSps:(NSData *)sps pps:(NSData *)pps{
	// no start code
	uint8_t*  parameterSetPointers[2] = {(uint8_t*)sps.bytes, (uint8_t*)pps.bytes};
	size_t parameterSetSizes[2] = {sps.length, sps.length};

	OSStatus status;
	status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2,
																 (const uint8_t *const*)parameterSetPointers,
																 parameterSetSizes, 4,
																 &_formatDesc);

//	NSLog(@"\t\t Creation of CMVideoFormatDescription: %@", (status == noErr) ? @"successful!" : @"failed...");
	if(status != noErr) NSLog(@"\t\t Format Description ERROR type: %d", (int)status);
}

- (void)processFrame:(NSData *)frame pts:(double)pts{
	uint8_t *pNal = (uint8_t*)[frame bytes];
	//int nal_ref_idc = pNal[0] & 0x60;
	int nal_type = pNal[0] & 0x1f;
	//NSLog(@"NALU Type \"%@\"", naluTypesStrings[nal_type]);

	CMSampleBufferRef sampleBuffer = NULL;
	CMBlockBufferRef blockBuffer = NULL;

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

//		NSLog(@"\t\t BlockBufferCreation: \t %@", (status == kCMBlockBufferNoErr) ? @"successful!" : @"failed...");

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

		if(status == noErr){
			// set some values of the sample buffer's attachments
			CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
			CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
			CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
			// either send the samplebuffer to a VTDecompressionSession or to an AVSampleBufferDisplayLayer
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			[_videoLayer performSelector:@selector(enqueueSampleBuffer:) withObject:(__bridge id)(sampleBuffer) afterDelay:pts];
			CFRelease(blockBuffer);
			CFRelease(sampleBuffer);
		});
	}
}
//
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
//		// allocate enough data to fit the SPS and PPS parameters into our data objects.
//		// VTD doesn't want you to include the start code header (4 bytes long) so we add the - 4 here
//		sps = malloc(_spsSize - 4);
//		pps = malloc(_ppsSize - 4);
//		
//		// copy in the actual sps and pps values, again ignoring the 4 byte header
//		memcpy (sps, &frame[4], _spsSize-4);
//		memcpy (pps, &frame[_spsSize+4], _ppsSize-4);
//		
//		// now we set our H264 parameters
//		uint8_t*  parameterSetPointers[2] = {sps, pps};
//		size_t parameterSetSizes[2] = {_spsSize-4, _ppsSize-4};
//		
//		status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2,
//																	 (const uint8_t *const*)parameterSetPointers,
//																	 parameterSetSizes, 4,
//																	 &_formatDesc);
//		
//		NSLog(@"\t\t Creation of CMVideoFormatDescription: %@", (status == noErr) ? @"successful!" : @"failed...");
//		if(status != noErr) NSLog(@"\t\t Format Description ERROR type: %d", (int)status);
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
