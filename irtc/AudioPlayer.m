//
//  AudioPlayer.m
//  VideoTest
//
//  Created by ideawu on 2/29/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "AudioPlayer.h"
#import <AudioToolbox/AudioToolbox.h>

#define BUF_SIZE 5;

// AudioQueueSetParameter ( queue, kAudioQueueParam_Volume, gain )

@interface AudioPlayer(){
	BOOL _inited;
	BOOL _playing;
	int _buffering_count;
}
@property AudioQueueRef queue;
@property AudioStreamBasicDescription format;
@property AudioStreamPacketDescription aspd;
@end


@implementation AudioPlayer

+ (AudioPlayer *)AACPlayerWithSampleRate:(int)sampleRate channels:(int)channels{
	AudioPlayer *ret = [[AudioPlayer alloc] init];
	AudioStreamBasicDescription _format = {0};
	_format.mFormatID = kAudioFormatMPEG4AAC;
	_format.mSampleRate = sampleRate;
	_format.mChannelsPerFrame = channels;
	_format.mFramesPerPacket = 1024;
	ret.format = _format;
	return ret;
}

- (id)init{
	self = [super init];
	
	_inited = NO;
	_playing = NO;
	_buffering_count = 0;

	_format.mFormatID = kAudioFormatLinearPCM;
	_format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | kAudioFormatFlagIsBigEndian;
	_format.mChannelsPerFrame = 2;
	_format.mSampleRate = 44100;
	_format.mBitsPerChannel = 8 * _format.mChannelsPerFrame;
	_format.mFramesPerPacket = 1;
	_format.mBytesPerPacket = _format.mChannelsPerFrame * (_format.mBitsPerChannel / 8);
	_format.mBytesPerFrame = _format.mBytesPerPacket;
	_format.mReserved = 0;

	return self;
}

- (void)dealloc{
	[self stop];
}

- (id)setSampleRate:(int)sampleRate channels:(int)channels{
	_format.mSampleRate = sampleRate;
	_format.mChannelsPerFrame = channels;
	_format.mBitsPerChannel = 8 * _format.mChannelsPerFrame;
	return self;
}

- (void)stop{
	if(_queue){
		AudioQueueStop(_queue, false);
		AudioQueueDispose(_queue, false);
		_queue = NULL;
	}
}

static void callback(void *custom_data, AudioQueueRef _queue, AudioQueueBufferRef buffer){
	AudioPlayer *player = (__bridge AudioPlayer *)custom_data;
	[player onCallback:buffer];
}

- (void)onCallback:(AudioQueueBufferRef)buffer{
	_buffering_count --;
	NSLog(@"callback %d", _buffering_count);
	if(_buffering_count == 1){
		//NSLog(@"silence added");
		//[self addSilence];
	}
	if(_buffering_count == 0){
		@synchronized(self){
			_playing = NO;
		}
		NSLog(@"AQ paused");
		AudioQueuePause(_queue);
	}
	AudioQueueFreeBuffer(_queue, buffer);
}

static NSString *formatIDtoString(int fID){
	return [NSString stringWithFormat:@"'%c%c%c%c'", (char)(fID>>24)&255, (char)(fID>>16)&255, (char)(fID>>8)&255, (char)fID&255];
}

- (void)printFormat:(AudioStreamBasicDescription)format name:(NSString *)name{
	log_debug(@"--- begin %@", name);
	log_debug(@"format.mFormatID:         %@", formatIDtoString(format.mFormatID));
	log_debug(@"format.mFormatFlags:      %d", format.mFormatFlags);
	log_debug(@"format.mSampleRate:       %f", format.mSampleRate);
	log_debug(@"format.mBitsPerChannel:   %d", format.mBitsPerChannel);
	log_debug(@"format.mChannelsPerFrame: %d", format.mChannelsPerFrame);
	log_debug(@"format.mBytesPerFrame:    %d", format.mBytesPerFrame);
	log_debug(@"format.mFramesPerPacket:  %d", format.mFramesPerPacket);
	log_debug(@"format.mBytesPerPacket:   %d", format.mBytesPerPacket);
	log_debug(@"format.mReserved:         %d", format.mReserved);
	log_debug(@"--- end %@", name);
}

- (void)setupAQ{
	[self printFormat:_format name:@""];
	
	OSStatus err;
	err = AudioQueueNewOutput(&_format, callback, (__bridge void *)(self), NULL, NULL, 0, &_queue);
	if(err){
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		NSLog(@"line: %d, error: %@", __LINE__, error);
		return;
	}
	NSLog(@"AQ setup");
}

- (void)appendData:(NSData *)data{
	if(!_inited){
		_inited = YES;
		[self setupAQ];
	}

	OSStatus err;
	AudioQueueBufferRef buffer;
	err = AudioQueueAllocateBuffer(_queue, (UInt32)data.length, &buffer);
	buffer->mAudioDataByteSize = (UInt32)data.length;
	memcpy(buffer->mAudioData, data.bytes, buffer->mAudioDataByteSize);
	
	_aspd.mStartOffset = 0;
	_aspd.mDataByteSize = (UInt32)data.length;
	_aspd.mVariableFramesInPacket = 0;
	err = AudioQueueEnqueueBuffer(_queue, buffer, 1, &_aspd);
//	err = AudioQueueEnqueueBuffer(_queue, buffer, 0, NULL);

//	err = AudioQueueEnqueueBufferWithParameters(_queue,
//												buffer,
//												0,
//												NULL,
//												0,//trimFramesAtStart,
//												0,//trimFramesAtEnd,
//												0, NULL, NULL, NULL);
	if(err){
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain
											 code:err
										 userInfo:nil];
		NSLog(@"AudioQueueEnqueueBuffer error: %d %@", err, [error description]);
	}
	
//	double duration = (double)buffer->mAudioDataByteSize / (_format.mSampleRate * _format.mBitsPerChannel * _format.mChannelsPerFrame / 8);
//	NSLog(@"add %d byte(s), duration: %.3f", buffer->mAudioDataByteSize, duration);
	_buffering_count ++;

	@synchronized(self){
		if(!_playing){
			// 对 AAC 特殊处理, 不知道为什么, AAC 必须 3 个以上才能 start
			if(_format.mFormatID == kAudioFormatMPEG4AAC && _buffering_count < 3){
				return;
			}
			_playing = YES;

			err = AudioQueueStart(_queue, NULL);
			if(err){
				NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
				NSLog(@"%d error %@", __LINE__, error);
			}else{
				NSLog(@"AQ started");
			}
		}
	}
}


@end
