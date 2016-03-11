//
//  AudioPlayer.m
//  VideoTest
//
//  Created by ideawu on 2/29/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "AudioPlayer.h"
#import <AudioToolbox/AudioToolbox.h>
#import "AudioBufferQueue.h"

typedef enum{
	PlayerStateNone,
	PlayerStatePause,
	PlayerStatePlaying,
}PlayerState;

// AudioQueueSetParameter ( queue, kAudioQueueParam_Volume, gain )

@interface AudioPlayer(){
	BOOL _inited;
	PlayerState _state;
	AudioBufferQueue *_buffers;
	int _count;
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

	_count = 0;

	_inited = NO;
	_state = PlayerStateNone;

	_buffers = nil;

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

//	double duration = 0.1;
//	int buffer_size;
//	if(_format.mBitsPerChannel > 0){
//		int bitrate = _format.mSampleRate * _format.mChannelsPerFrame * _format.mBitsPerChannel;
//		buffer_size = duration * bitrate / 8;
//	}else{
//		// TODO: 根据压缩后的 bitrate 估算
//		buffer_size = 4096;
//	}
//	log_debug(@"bytes_per_buffer: %d", _buffers.bytes_per_buffer);
//	UInt32 maxVBRPacketSize = sizeof(maxPacketSize);
//	AudioQueueGetProperty (
//						   audioQueue,
//						   kAudioQueueProperty_MaximumOutputPacketSize,
//						   // in Mac OS X v10.5, instead use
//						   //   kAudioConverterPropertyMaximumOutputPacketSize
//						   &maxPacketSize,
//						   &maxVBRPacketSize
//						   );

	_buffers = [[AudioBufferQueue alloc] initWithAudioQueue:_queue];
}

- (void)onCallback:(AudioQueueBufferRef)buffer{
	_count --;
	log_debug(@"callback %d", _count);
	buffer->mAudioDataByteSize = 0;
	buffer->mPacketDescriptionCount = 0;
	[_buffers pushFreeBuffer];

//	@synchronized(self){
//		if(_count == 0){
//			_state = PlayerStatePause;
//			NSLog(@"AQ paused");
//			AudioQueuePause(_queue);
//		}
//	}

	return;

	AudioQueueBufferRef audio_buf;
	audio_buf = [_buffers popReadyBuffer];

//	log_debug(@"");

	OSStatus err;
	err = AudioQueueEnqueueBuffer(_queue,
								  audio_buf,
								  audio_buf->mPacketDescriptionCount,
								  audio_buf->mPacketDescriptions);
	if(err){
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		NSLog(@"AudioQueueEnqueueBuffer error: %d %@", err, [error description]);
		return;
	}
}

- (void)startIfNeeded{
	OSStatus err;

	@synchronized(self){
		//if(_state == PlayerStateNone){
			AudioQueueBufferRef buffer;
			buffer = [_buffers popReadyBuffer];

			//			// 对 AAC 特殊处理, 不知道为什么, AAC 必须 3 个以上才能 start
			//			if(_format.mFormatID == kAudioFormatMPEG4AAC && _buffering_count < 3){
			//				return;
			//			}

		_count ++;
		log_debug(@"enqueue %d", _count);
			err = AudioQueueEnqueueBuffer(_queue,
										  buffer,
										  buffer->mPacketDescriptionCount,
										  buffer->mPacketDescriptions);
			if(err){
				NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
				NSLog(@"AudioQueueEnqueueBuffer error: %d %@", err, [error description]);
				return;
			}
//		}
		if(_state != PlayerStatePlaying && _count >= 3){
			_state = PlayerStatePlaying;
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

- (void)appendData:(NSData *)data{
	if(!_inited){
		_inited = YES;
		[self setupAQ];
	}

	double duration;
	double bitrate;
	if(_format.mBitsPerChannel > 0){
		bitrate = _format.mSampleRate * _format.mChannelsPerFrame * _format.mBitsPerChannel;
	}else{
		bitrate = 64000.0;
	}
	double buffering_time = 0.1;

	AudioQueueBufferRef buffer;
	buffer = [_buffers getFreeBuffer];

	if(buffer->mAudioDataByteSize + data.length > buffer->mAudioDataBytesCapacity){
		[_buffers popFreeBuffer];
//		log_debug(@"add ready");
		[_buffers pushReadyBuffer:buffer];
		[self startIfNeeded];
	}

	buffer = [_buffers getFreeBuffer];

	int offset = buffer->mAudioDataByteSize;
	buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mStartOffset = offset;
	buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mDataByteSize = (UInt32)data.length;
	memcpy(buffer->mAudioData + offset, data.bytes, data.length);
	buffer->mAudioDataByteSize += data.length;
	buffer->mPacketDescriptionCount ++;

	duration = buffer->mAudioDataByteSize / (bitrate/8);
	if(duration >= buffering_time || buffer->mAudioDataByteSize == buffer->mAudioDataBytesCapacity){
		[_buffers popFreeBuffer];
//		log_debug(@"add ready 2");
		[_buffers pushReadyBuffer:buffer];
		[self startIfNeeded];
	}

//	double duration = (double)buffer->mAudioDataByteSize / (_format.mSampleRate * _format.mBitsPerChannel * _format.mChannelsPerFrame / 8);
//	NSLog(@"add %d byte(s), duration: %.3f", buffer->mAudioDataByteSize, duration);

}


@end
