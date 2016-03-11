//
//  AudioFileWrapper.m
//  irtc
//
//  Created by ideawu on 3/11/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#include "inc.h"
#import "AudioFileWrapper.h"

@interface AudioFileWrapper(){
	ExtAudioFileRef _extAudioFile;
	AudioStreamBasicDescription _srcFormat;
	AudioStreamBasicDescription _dstFormat;
	NSMutableArray *_items;
}
@end

@implementation AudioFileWrapper

- (id)init{
	self = [super init];
	_items = [[NSMutableArray alloc] init];
	return self;
}

- (void)start{
	[self performSelectorInBackground:@selector(run) withObject:nil];
}

- (void)decode:(NSData *)audioData{
	@synchronized(_items){
		[_items addObject:audioData];
	}
}

- (void)run{
	AudioFileID         refAudioFileID;
	ExtAudioFileRef     inputFileID;
	
	OSStatus err;
	log_debug(@"aaa");
	err = AudioFileOpenWithCallbacks((__bridge void * _Nonnull)(self),
									 readProc, 0,
									 getSizeProc, 0,
									 kAudioFileAIFFType,
									 &refAudioFileID);
	log_debug(@"aaa");
//	err = AudioFileOpenWithCallbacks((__bridge void * _Nonnull)(audioData),
//									 readProc, 0,
//									 getSizeProc, 0,
//									 kAudioFileAAC_ADTSType,
//									 &refAudioFileID);
	if(err != noErr){
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		log_debug(@"%d error: %@", __LINE__, error);
	}
	log_debug(@"aaa");
	
	err = ExtAudioFileWrapAudioFileID(refAudioFileID, false, &inputFileID);
	if (err != noErr){
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		log_debug(@"%d error: %@", __LINE__, error);
	}
	
	// Client Audio Format Description
	AudioStreamBasicDescription clientFormat;
	memset(&clientFormat, 0, sizeof(clientFormat));
	clientFormat.mFormatID          = kAudioFormatLinearPCM;
	clientFormat.mFormatFlags       = kAudioFormatFlagsNativeFloatPacked;
	//clientFormat.mFormatFlags = kLinearPCMFormatFlagIsBigEndian | kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
	clientFormat.mSampleRate        = 48000;
	clientFormat.mFramesPerPacket   = 1;
	clientFormat.mChannelsPerFrame  = 2;
	clientFormat.mBitsPerChannel    = 16;
	clientFormat.mBytesPerPacket    = clientFormat.mBytesPerFrame = 2 * clientFormat.mChannelsPerFrame;

	//Output Audio Format Description
	AudioStreamBasicDescription outputFormat;
	memset(&outputFormat, 0, sizeof(outputFormat));
	outputFormat.mFormatID          = kAudioFormatMPEG4AAC;
	outputFormat.mFormatFlags       = kMPEG4Object_AAC_Main;
	outputFormat.mSampleRate        = 44100;
	outputFormat.mChannelsPerFrame  = 2;
	outputFormat.mBitsPerChannel    = 0;
	outputFormat.mBytesPerFrame     = 0;
	outputFormat.mBytesPerPacket    = 0;
	outputFormat.mFramesPerPacket   = 1024;
	
	UInt32 outputFormatSize = sizeof(outputFormat);
	err = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &outputFormatSize, &outputFormat);
	if(err != noErr)
		log_debug(@"could not set the output format with status code %i \n",err);
	
	int size = sizeof(clientFormat);
	err = ExtAudioFileSetProperty(inputFileID, kExtAudioFileProperty_ClientDataFormat, size, &clientFormat);
	if(err != noErr)
		log_debug(@"error on ExtAudioFileSetProperty for input File with result code %i \n", err);
	
	
	int totalFrames = 0;
	UInt32 encodedBytes = 0;
	
	while (1) {
		UInt32 bufferByteSize       = 1024;
		char srcBuffer[bufferByteSize];
		UInt32 numFrames = (bufferByteSize/clientFormat.mBytesPerFrame);
		
		AudioBufferList fillBufList;
		fillBufList.mNumberBuffers  = 1;
		fillBufList.mBuffers[0].mNumberChannels     = clientFormat.mChannelsPerFrame;
		fillBufList.mBuffers[0].mDataByteSize       = bufferByteSize;
		fillBufList.mBuffers[0].mData               = srcBuffer;

		err = ExtAudioFileRead(inputFileID, &numFrames, &fillBufList);
		
		if (err != noErr) {
			log_debug(@"Error on ExtAudioFileRead with result code %i \n", err);
			totalFrames = 0;
			break;
		}
		if (!numFrames)
			break;
		
		totalFrames = totalFrames + numFrames;
		encodedBytes += numFrames  * clientFormat.mBytesPerFrame;
		
		log_debug(@"decoded %d bytes", numFrames * clientFormat.mBytesPerFrame);
	}
	
	//Clean up
	
	ExtAudioFileDispose(inputFileID);
	AudioFileClose(refAudioFileID);
	
}

- (NSData *)read{
	while(1){
		@synchronized(_items) {
			if(_items.count == 0){
				usleep(100 * 1000);
				continue;
				return nil;
			}
			NSData *data = _items.firstObject;
			[_items removeObjectAtIndex:0];
			return data;
		}
	}
}

// AudioFile_ReadProc
static OSStatus readProc(void* clientData,
						 SInt64 position,
						 UInt32 requestCount,
						 void* buffer,
						 UInt32* actualCount)
{
	log_debug("");
	AudioFileWrapper *me = (__bridge AudioFileWrapper *)clientData;
	NSData *data = [me read];
	log_debug(@"%s, %d bytes", __func__, (int)data.length);
	if(!data){
		return -1;
	}
	
	size_t dataSize = data.length;
	size_t bytesToRead = 0;
	
	if(position < dataSize) {
		size_t bytesAvailable = dataSize - position;
		bytesToRead = requestCount <= bytesAvailable ? requestCount : bytesAvailable;
		
		[data getBytes: buffer range:NSMakeRange(position, bytesToRead)];
	} else {
		log_debug(@"data was not read \n");
		bytesToRead = 0;
	}
	
	if(actualCount)
		*actualCount = (UInt32)bytesToRead;
	
	return noErr;
}

// AudioFile_GetSizeProc
static SInt64 getSizeProc(void* clientData) {
	static i = 0;
	if(i++ > 0){
		return 0;
	}
	log_debug(@"%s, %d bytes", __func__, 86002);
	return 86002;
	NSData *inAudioData = (__bridge NSData *) clientData;
	log_debug(@"%s, %d bytes", __func__, (int)inAudioData.length);
	size_t dataSize = inAudioData.length;
	return dataSize;
}

@end
