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

typedef struct{
	int total;
	int count;
	int index;
	AudioQueueBufferRef items;

}BufferList;

@interface AudioPlayer(){
	BOOL _started;
	BOOL _playing;
	AudioQueueBufferRef _silence_buffer;
	int _buffering_count;
	
	BufferList _buffers;
}
@property AudioStreamPacketDescription aspd;
//@property (assign, nonatomic) AudioStreamPacketDescription *packetDescriptions;
//@property (assign, nonatomic) UInt32 numberOfPacketDescriptions;
@end


@implementation AudioPlayer

- (id)init{
	self = [super init];
	
	_started = NO;
	_playing = NO;
	_buffering_count = 0;
	
//	self.packetDescriptions = malloc(sizeof(AudioStreamPacketDescription) * 512);
//	self.numberOfPacketDescriptions = 0;
	
	_buffers.total = 5;
	_buffers.count = 0;
	_buffers.index = 0;
	_buffers.items = malloc(_buffers.total * sizeof(AudioQueueBufferRef));

	_format.mSampleRate = 44100.0;
	_format.mFormatID = kAudioFormatLinearPCM;
	_format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	_format.mBitsPerChannel = 8 * sizeof(short);
	_format.mChannelsPerFrame = 2;
	_format.mBytesPerFrame = sizeof(short) * _format.mChannelsPerFrame;
	_format.mFramesPerPacket = 1;
	_format.mBytesPerPacket = _format.mBytesPerFrame * _format.mFramesPerPacket;
	_format.mReserved = 0;

	return self;
}

- (void)stop{
	AudioQueueStop(_queue, false);
	AudioQueueDispose(_queue, false);
	AudioQueueFreeBuffer(_queue, _silence_buffer);
}

static void callback(void *custom_data, AudioQueueRef _queue, AudioQueueBufferRef buffer){
	AudioPlayer *player = (__bridge AudioPlayer *)custom_data;
	[player onCallback:buffer];
}

- (void)onCallback:(AudioQueueBufferRef)buffer{
	if(buffer == _silence_buffer){
		NSLog(@"silence end");
		return;
	}
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
	
	double duration = 0.1;
	int nbytes = duration * _format.mSampleRate * _format.mBitsPerChannel * _format.mChannelsPerFrame / 8;
	nbytes = 1024;
	NSLog(@"silent nbytes: %d", nbytes);
	err = AudioQueueAllocateBuffer(_queue, nbytes, &_silence_buffer);
	if(err){
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		NSLog(@"line: %d, error: %@", __LINE__, error);
		return;
	}
	_silence_buffer->mAudioDataByteSize = nbytes;
	memset(_silence_buffer->mAudioData, 0, nbytes);
	//[self addSilence];
	//err = AudioQueueStart(_queue, NULL);
	NSLog(@"AQ setup");
}

- (void)addSilence{
	OSStatus err;
	err = AudioQueueEnqueueBuffer(_queue, _silence_buffer, 0, NULL);
	if(err){
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain
											 code:err
										 userInfo:nil];
		NSLog(@"AudioQueueEnqueueBuffer error: %d %@", err, [error description]);
	}
}

- (void)appendData:(NSData *)data audioFormat:(AudioStreamBasicDescription)format{
	if(!_started){
		_started = YES;
		_format = format;
		[self setupAQ];
	}

	OSStatus err;
	AudioQueueBufferRef buffer;
	err = AudioQueueAllocateBuffer(_queue, (UInt32)data.length, &buffer);
	buffer->mAudioDataByteSize = (UInt32)data.length;
	memcpy(buffer->mAudioData, data.bytes, buffer->mAudioDataByteSize);
	
//	_aspd.mStartOffset = 0;
//	_aspd.mDataByteSize = (UInt32)data.length;
//	_aspd.mVariableFramesInPacket = 1024;
//	err = AudioQueueEnqueueBuffer(_queue, buffer, 1, &_aspd);
	err = AudioQueueEnqueueBuffer(_queue, buffer, 0, NULL);

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
