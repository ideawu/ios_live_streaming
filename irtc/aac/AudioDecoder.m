//
//  AudioDecoder.m
//  irtc
//
//  Created by ideawu on 3/10/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "AudioDecoder.h"
#import "AACCodec.h"

@interface AudioDecoder(){
	AudioFileStreamID _audioFileStream;
	void (^_callback)(NSData *pcm, double duration);
}
@property AACCodec *codec;
@end

@implementation AudioDecoder

- (id)init{
	self = [super init];
	return self;
}

- (void)start:(void (^)(NSData *pcm, double duration))callback{
	_callback = callback;
	if(!_codec){
		_codec = [[AACCodec alloc] init];
		
		AudioStreamBasicDescription src = {0};
		AudioStreamBasicDescription dst = {0};
		
		// TODO: parse ADTS
		src.mFormatID = kAudioFormatMPEG4AAC;
		src.mFormatFlags = kMPEG4Object_AAC_LC;
		src.mChannelsPerFrame = 2;
		src.mSampleRate = 48000;
		src.mFramesPerPacket = 1024;
		src.mBitsPerChannel = 16;
		src.mBytesPerPacket = src.mChannelsPerFrame * (src.mBitsPerChannel / 8);
		src.mBytesPerFrame = src.mBytesPerPacket;
		
		dst.mFormatID = kAudioFormatLinearPCM;
		dst.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
		//dst.mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
		dst.mSampleRate = src.mSampleRate;
		dst.mChannelsPerFrame = src.mChannelsPerFrame;
		dst.mFramesPerPacket = 1;
		dst.mBitsPerChannel = src.mBitsPerChannel;
		dst.mBytesPerPacket = dst.mChannelsPerFrame * (dst.mBitsPerChannel / 8);
		dst.mBytesPerFrame = dst.mBytesPerPacket;
		
		[_codec setupCodecWithFormat:src dstFormat:dst];
		[_codec start:_callback];
	}
}

- (void)shutdown{
	if(_codec){
		[_codec shutdown];
	}
}

- (void)decode:(NSData *)aac{
	[_codec decodeAAC:aac];
}


//- (void)appendData:(NSData *)data pts:(double)pts{
//	OSStatus err = noErr;
//	err = AudioFileStreamParseBytes(_audioFileStream, (UInt32)data.length, data.bytes, 0);
//	if(err){
//		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
//		NSLog(@"%d error %@", __LINE__, error);
//	}
//}

//#pragma mark - AudioFileStream things
//
//void MyPacketsProc(void *, UInt32, UInt32, const void *, AudioStreamPacketDescription *);
//void MyPropertyListenerProc(void *, AudioFileStreamID, AudioFileStreamPropertyID, UInt32 *);
//
//- (void)setupAudioFileStream{
//	OSStatus err = AudioFileStreamOpen((__bridge void *)(self),
//									   MyPropertyListenerProc,
//									   MyPacketsProc,
//									   kAudioFileAAC_ADTSType,
//									   &_audioFileStream);
//	if(err){
//		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
//		NSLog(@"%d error %@", __LINE__, error);
//	}
//}
//
//- (void)onFormatReady{
//	UInt32 size = sizeof(dst);
//	OSStatus err;
//	err = AudioFileStreamGetProperty(_audioFileStream, kAudioFileStreamProperty_DataFormat, &size, &dst);
//	if(err){
//		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
//		NSLog(@"%d error %@", __LINE__, error);
//	}
//	
//	// get the cookie size
//	UInt32 cookieSize;
//	Boolean writable;
//	err = AudioFileStreamGetPropertyInfo(_audioFileStream,
//										 kAudioFileStreamProperty_MagicCookieData,
//										 &cookieSize, &writable);
//	if (err) { NSLog(@"info kAudioFileStreamProperty_MagicCookieData"); return; }
//	printf("cookieSize %d\n", (unsigned int)cookieSize);
//	
//	// get the cookie data
//	void* cookieData = calloc(1, cookieSize);
//	err = AudioFileStreamGetProperty(_audioFileStream,
//									 kAudioFileStreamProperty_MagicCookieData,
//									 &cookieSize, cookieData);
//	if (err) { NSLog(@"get kAudioFileStreamProperty_MagicCookieData"); free(cookieData); return; }
//	
////	// set the cookie on the queue.
////	err = AudioQueueSetProperty(audioPlayer.queue, kAudioQueueProperty_MagicCookie, cookieData, cookieSize);
//	free(cookieData);
//	
////	if (err) { NSLog(@"set kAudioQueueProperty_MagicCookie"); return; }
//	
//	// listen for kAudioQueueProperty_IsRunning
////	err = AudioQueueAddPropertyListener(audioPlayer.queue, kAudioQueueProperty_IsRunning, MyAudioQueueIsRunningCallback, NULL);
////	if (err) { NSLog(@"AudioQueueAddPropertyListener"); return; }
//}
//
//
//void MyPropertyListenerProc(void *							inClientData,
//							AudioFileStreamID				inAudioFileStream,
//							AudioFileStreamPropertyID		inPropertyID,
//							UInt32 *						ioFlags)
//{
//	AudioDecoder *decoder = (__bridge AudioDecoder *)inClientData;
//	NSLog(@"found property '%c%c%c%c'", (char)(inPropertyID>>24)&255, (char)(inPropertyID>>16)&255, (char)(inPropertyID>>8)&255, (char)inPropertyID&255);
//	if(inPropertyID == kAudioFileStreamProperty_ReadyToProducePackets){
//		[decoder onFormatReady];
//	}
//}
//
//void MyPacketsProc(void *							inClientData,
//				   UInt32							inNumberBytes,
//				   UInt32							inNumberPackets,
//				   const void *					inInputData,
//				   AudioStreamPacketDescription	*inPacketDescriptions)
//{
//	// this is called by audio file stream when it finds packets of audio
//	printf("got data.  bytes: %d  packets: %d\n", (unsigned int)inNumberBytes, (unsigned int)inNumberPackets);
//}

@end

