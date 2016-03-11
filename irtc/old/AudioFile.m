//
//  AudioFile.m
//  irtc
//
//  Created by ideawu on 16-3-10.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import <AudioToolbox/AudioToolbox.h>
#import "AudioFile.h"

const UInt32 kSrcBufSize = 32768;

@interface AudioFile(){
	ExtAudioFileRef _outfile;
	AudioStreamBasicDescription _format;
	AudioStreamBasicDescription _srcFormat;
}
@property NSURL *url;
@end


@implementation AudioFile

- (id)init{
	self = [super init];
	
	_outfile = NULL;
	NSString *output = [NSTemporaryDirectory() stringByAppendingFormat:@"/b.aac"];
	_url = [NSURL fileURLWithPath:output];
	
	return self;
}

- (void)dealloc{
	if(_outfile){
		ExtAudioFileDispose(_outfile);
	}
}

- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	
}

- (void)setupFromSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	_srcFormat = *CMAudioFormatDescriptionGetStreamBasicDescription((CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer));

	OSStatus err;
	UInt32 size;
	int outputBitRate = 80000;
	
	_format.mFormatID = kAudioFormatMPEG4AAC;
	_format.mChannelsPerFrame = 2;
	_format.mSampleRate = 0;

	err = ExtAudioFileCreateWithURL((__bridge CFURLRef)_url,
									kAudioFileAAC_ADTSType,
									&_format,
									NULL,
									kAudioFileFlags_EraseFile,
									&_outfile);
	if(err != 0){
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		NSLog(@"%d error: %d, %@", __LINE__, err, error);
	}
	
	AudioStreamBasicDescription clientFormat = (_srcFormat.mFormatID == kAudioFormatLinearPCM ? _srcFormat : _format);
	size = sizeof(clientFormat);
	err = ExtAudioFileSetProperty(_outfile, kExtAudioFileProperty_ClientDataFormat, size, &clientFormat);
	if(err != 0){
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		NSLog(@"%d error: %d, %@", __LINE__, err, error);
	}

	if(outputBitRate > 0){
		NSLog(@"Dest bit rate: %d", (int)outputBitRate);
		AudioConverterRef outConverter;
		size = sizeof(outConverter);
		err = ExtAudioFileGetProperty(_outfile, kExtAudioFileProperty_AudioConverter, &size, &outConverter);
		if(err != 0){
			NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
			NSLog(@"%d error: %d, %@", __LINE__, err, error);
		}
		
		err = AudioConverterGetPropertyInfo(outConverter, kAudioConverterApplicableEncodeBitRates, &size, NULL);
		if(err != 0){
			NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
			NSLog(@"%d error: %d, %@", __LINE__, err, error);
		}
		AudioValueRange *bitrates;
		bitrates = malloc(size);
		err = AudioConverterGetProperty(outConverter, kAudioConverterApplicableEncodeBitRates, &size, bitrates);
		if(err != 0){
			NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
			NSLog(@"%d error: %d, %@", __LINE__, err, error);
		}
		//		if(noErr == err) {
		//			unsigned bitrateCount = size / sizeof(AudioValueRange);
		//			unsigned n;
		//			for(n = 0; n < bitrateCount; ++n) {
		//				unsigned long minRate = (unsigned long) bitrates[n].mMinimum;
		//				unsigned long maxRate = (unsigned long) bitrates[n].mMaximum;
		//				NSLog(@"%d %d", (int)minRate, (int)maxRate);
		//			}
		//		}
		
		err = AudioConverterSetProperty(outConverter, kAudioConverterEncodeBitRate, sizeof(outputBitRate), &outputBitRate);
		if(err != 0){
			NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
			NSLog(@"%d error: %d, %@", __LINE__, err, error);
		}
	}
}

+ (AudioStreamBasicDescription)getAudioFileFormat:(NSURL *)url{
	AudioStreamBasicDescription format;
	
	AudioFileID fileID  = nil;
	OSStatus err=noErr;
	err = AudioFileOpenURL( (__bridge CFURLRef)url, kAudioFileReadPermission, 0, &fileID );
	if( err != noErr ) {
		NSLog( @"AudioFileOpenURL failed" );
	}
	UInt32 size;
	AudioFileGetPropertyInfo(fileID, kAudioFilePropertyFormatList, &size, NULL);
	UInt32 numFormats = size / sizeof(AudioFormatListItem);
	AudioFormatListItem *formatList = malloc(numFormats * sizeof(AudioFormatListItem));
	
	// we need to reassess the actual number of formats when we get it
	AudioFileGetProperty(fileID, kAudioFilePropertyFormatList, &size, formatList);
	numFormats = size / sizeof(AudioFormatListItem);
	if (numFormats == 1) {
		format = formatList[0].mASBD;
	} else {
		// now we should look to see which decoders we have on the system
		AudioFormatGetPropertyInfo(kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &size);
		UInt32 numDecoders = size / sizeof(OSType);
		OSType *decoderIDs = malloc(numDecoders * sizeof(OSType));
		AudioFormatGetProperty(kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &size, decoderIDs);
		unsigned int i = 0;
		for (; i < numFormats; ++i) {
			OSType decoderID = formatList[i].mASBD.mFormatID;
			bool found = false;
			for (unsigned int j = 0; j < numDecoders; ++j) {
				if (decoderID == decoderIDs[j]) {
					found = true;
					break;
				}
			}
			if (found) break;
		}
		free(decoderIDs);
		
		if (i >= numFormats) {
			NSLog(@"Cannot play any of the formats in this file");
		}
		format = formatList[i].mASBD;
	}
	free(formatList);
	return format;
}

+ (void)printFormat:(AudioStreamBasicDescription)format{
	NSLog(@"--- begin");
	NSLog(@"format.mSampleRate:       %f", format.mSampleRate);
	NSLog(@"format.mBitsPerChannel:   %d", format.mBitsPerChannel);
	NSLog(@"format.mChannelsPerFrame: %d", format.mChannelsPerFrame);
	NSLog(@"format.mBytesPerFrame:    %d", format.mBytesPerFrame);
	NSLog(@"format.mFramesPerPacket:  %d", format.mFramesPerPacket);
	NSLog(@"format.mBytesPerPacket:   %d", format.mBytesPerPacket);
	NSLog(@"--- end");
}

+ (void)convertFile{
	int outputBitRate = 80000;

	NSString *input = [NSTemporaryDirectory() stringByAppendingFormat:@"/a.aif"];
	NSString *output = [NSTemporaryDirectory() stringByAppendingFormat:@"/b.aac"];
	NSURL *inUrl = [NSURL fileURLWithPath:input];
	NSURL *outUrl = [NSURL fileURLWithPath:output];
	CFURLRef inputFileURL = (__bridge CFURLRef)(inUrl);
	CFURLRef outputFileURL = (__bridge CFURLRef)(outUrl);
	AudioStreamBasicDescription inputFormat;
	AudioStreamBasicDescription outputFormat;
	
//	inputFormat.mFormatID = kAudioFormatLinearPCM;
//	inputFormat.mSampleRate = 44100;
//	inputFormat.mChannelsPerFrame = 1;
//	inputFormat.mBytesPerFrame = 2 * inputFormat.mChannelsPerFrame;
//	inputFormat.mFramesPerPacket = 1;
//	inputFormat.mFormatFlags = kLinearPCMFormatFlagIsPacked | kLinearPCMFormatFlagIsSignedInteger;
	
	inputFormat = [AudioFile getAudioFileFormat:inUrl];
	[AudioFile printFormat:inputFormat];
	
	outputFormat.mFormatID = kAudioFormatMPEG4AAC;
	outputFormat.mChannelsPerFrame = inputFormat.mChannelsPerFrame;
	// 如果设置 bitrate, 应该让编码器自己决定 samplerate
	if(outputBitRate){
		outputFormat.mSampleRate = 0;
	}else{
		outputFormat.mSampleRate = inputFormat.mSampleRate;
	}
	//outputFormat.mBitsPerChannel = 16; // 不能设置, Mac 会失败
	//outputFormat.mBytesPerPacket = outputFormat.mChannelsPerFrame * (outputFormat.mBitsPerChannel / 8);

	ExtAudioFileRef infile;
	
	OSStatus err;
	err = ExtAudioFileOpenURL(inputFileURL, &infile);
	if(err != 0){
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		NSLog(@"%d error: %d, %@", __LINE__, err, error);
	}
	
	[AudioFile printFormat:outputFormat];
	
	AudioStreamBasicDescription clientFormat = (inputFormat.mFormatID == kAudioFormatLinearPCM ? inputFormat : outputFormat);
	UInt32 size = sizeof(clientFormat);
	err = ExtAudioFileSetProperty(infile, kExtAudioFileProperty_ClientDataFormat, size, &clientFormat);
	if(err != 0){
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		NSLog(@"%d error: %d, %@", __LINE__, err, error);
	}
	[AudioFile printFormat:clientFormat];
	
	
	ExtAudioFileRef outfile;
	err = ExtAudioFileCreateWithURL(outputFileURL, kAudioFileAAC_ADTSType, &outputFormat, NULL, kAudioFileFlags_EraseFile, &outfile);
	if(err != 0){
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		NSLog(@"%d error: %d, %@", __LINE__, err, error);
	}

	size = sizeof(clientFormat);
	err = ExtAudioFileSetProperty(outfile, kExtAudioFileProperty_ClientDataFormat, size, &clientFormat);
	if(err != 0){
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		NSLog(@"%d error: %d, %@", __LINE__, err, error);
	}
	
	if(outputBitRate > 0){
		NSLog(@"Dest bit rate: %d", (int)outputBitRate);
		AudioConverterRef outConverter;
		size = sizeof(outConverter);
		err = ExtAudioFileGetProperty(outfile, kExtAudioFileProperty_AudioConverter, &size, &outConverter);
		if(err != 0){
			NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
			NSLog(@"%d error: %d, %@", __LINE__, err, error);
		}
		
		err = AudioConverterGetPropertyInfo(outConverter, kAudioConverterApplicableEncodeBitRates, &size, NULL);
		if(err != 0){
			NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
			NSLog(@"%d error: %d, %@", __LINE__, err, error);
		}
		AudioValueRange *bitrates;
		bitrates = malloc(size);
		err = AudioConverterGetProperty(outConverter, kAudioConverterApplicableEncodeBitRates, &size, bitrates);
		if(err != 0){
			NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
			NSLog(@"%d error: %d, %@", __LINE__, err, error);
		}
//		if(noErr == err) {
//			unsigned bitrateCount = size / sizeof(AudioValueRange);
//			unsigned n;
//			for(n = 0; n < bitrateCount; ++n) {
//				unsigned long minRate = (unsigned long) bitrates[n].mMinimum;
//				unsigned long maxRate = (unsigned long) bitrates[n].mMaximum;
//				NSLog(@"%d %d", (int)minRate, (int)maxRate);
//			}
//		}
		
		err = AudioConverterSetProperty(outConverter, kAudioConverterEncodeBitRate, sizeof(outputBitRate), &outputBitRate);
		if(err != 0){
			NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
			NSLog(@"%d error: %d, %@", __LINE__, err, error);
		}
	}
	
	// we have changed the converter, so we should do this in case
	// setting a converter property changes the converter used by ExtAF in some manner
	CFArrayRef config = NULL;
	err = ExtAudioFileSetProperty(outfile, kExtAudioFileProperty_ConverterConfig, sizeof(config), &config);
	if(err != 0){
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		NSLog(@"%d ouput error: %d, %@", __LINE__, err, error);
	}
	
	// set up buffers
	char srcBuffer[kSrcBufSize];
	
	while (1){
		AudioBufferList fillBufList;
		fillBufList.mNumberBuffers = 1;
		fillBufList.mBuffers[0].mNumberChannels = inputFormat.mChannelsPerFrame;
		fillBufList.mBuffers[0].mDataByteSize = kSrcBufSize;
		fillBufList.mBuffers[0].mData = srcBuffer;
		
		// client format is always linear PCM - so here we determine how many frames of lpcm
		// we can read/write given our buffer size
		UInt32 numFrames = (kSrcBufSize / clientFormat.mBytesPerFrame);
		
		//printf("test %d\n", numFrames);
		
		err = ExtAudioFileRead (infile, &numFrames, &fillBufList);
		if (!numFrames) {
			break;
		}
		
		err = ExtAudioFileWrite(outfile, numFrames, &fillBufList);
		if(err != 0){
			NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
			NSLog(@"%d ouput error: %d, %@", __LINE__, err, error);
			break;
		}
	}
	
	// close
	ExtAudioFileDispose(outfile);
	ExtAudioFileDispose(infile);
	NSLog(@"done");

}

@end
