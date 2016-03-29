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
		src.mFormatFlags = 0;
		src.mChannelsPerFrame = 2;
		src.mSampleRate = 48000;
		src.mFramesPerPacket = 1024;
		src.mBitsPerChannel = 16;
		src.mBytesPerPacket = src.mChannelsPerFrame * (src.mBitsPerChannel / 8);
		src.mBytesPerFrame = src.mBytesPerPacket;
		
		dst.mFormatID = kAudioFormatLinearPCM;
		//dst.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
		dst.mFormatFlags = kLinearPCMFormatFlagIsBigEndian | kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
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

@end

