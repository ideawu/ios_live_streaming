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

typedef struct{
	int total;
	int count;
	int index;
	AudioQueueBufferRef items;

}BufferList;

@interface AudioPlayer(){
	AudioQueueRef _queue;
	BOOL _started;
	BOOL _playing;
	AudioQueueBufferRef _silence_buffer;
	int _buffering_count;
	
	BufferList _buffers;
}
@property (assign, nonatomic) AudioStreamPacketDescription *packetDescriptions;
@property (assign, nonatomic) UInt32 numberOfPacketDescriptions;
@end


@implementation AudioPlayer

- (id)init{
	self = [super init];
	
	_started = NO;
	_playing = NO;
	_buffering_count = 0;
	
	self.packetDescriptions = malloc(sizeof(AudioStreamPacketDescription) * 512);
	self.numberOfPacketDescriptions = 0;
	
	_buffers.total = 5;
	_buffers.count = 0;
	_buffers.index = 0;
	_buffers.items = malloc(_buffers.total * sizeof(AudioQueueBufferRef));

	return self;
}

- (void)stop{
	AudioQueueStop(_queue, false);
	AudioQueueDispose(_queue, false);
	AudioQueueFreeBuffer(_queue, _silence_buffer);
}

// 注意: 如果AQ播放完了队列, 它将无法再播放, 这个非常坑!
// 所以, 你必须永远保持播放队列不为空. 可以填充无声数据进去.
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
		_playing = NO;
		NSLog(@"AQ paused");
		AudioQueuePause(_queue);
	}
	AudioQueueFreeBuffer(_queue, buffer);
}

- (void)setupAQ:(AudioStreamBasicDescription)format{
	//		UInt32 num_channels = 1;
	//		AudioStreamBasicDescription format;
	//		format.mSampleRate = 44100.0;
	//		format.mFormatID = kAudioFormatLinearPCM;
	//		format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	//		format.mBitsPerChannel = 8 * sizeof(short);
	//		format.mChannelsPerFrame = num_channels;
	//		format.mBytesPerFrame = sizeof(short) * num_channels;
	//		format.mFramesPerPacket = 1;
	//		format.mBytesPerPacket = format.mBytesPerFrame * format.mFramesPerPacket;
	//		format.mReserved = 0;
	NSLog(@"format.mSampleRate:      %f", format.mSampleRate);
	NSLog(@"format.mBitsPerChannel:  %d", format.mBitsPerChannel);
	NSLog(@"mChannelsPerFrame:       %d", format.mChannelsPerFrame);
	NSLog(@"format.mBytesPerFrame:   %d", format.mBytesPerFrame);
	NSLog(@"format.mFramesPerPacket: %d", format.mFramesPerPacket);
	NSLog(@"format.mBytesPerPacket:  %d", format.mBytesPerPacket);
	
	OSStatus err;
	err = AudioQueueNewOutput(&format, callback, (__bridge void *)(self), NULL, NULL, 0, &_queue);
	if(err){
		NSLog(@"%d error", __LINE__);
	}
	
	int nbytes = 4096;
	err = AudioQueueAllocateBuffer(_queue, nbytes, &_silence_buffer);
	if(err){
		NSLog(@"%d error", __LINE__);
		return;
	}
	_silence_buffer->mAudioDataByteSize = nbytes;
	memset(_silence_buffer->mAudioData, 0, nbytes);
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

- (void)appendSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	if(!_started){
		_started = YES;
		AudioStreamBasicDescription format = *CMAudioFormatDescriptionGetStreamBasicDescription((CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer));
		[self setupAQ:format];
	}
	
	CMBlockBufferRef blockBuffer;
	AudioBufferList audioBufferList;
	
	OSStatus err;
	err = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
															sampleBuffer,
															NULL,
															&audioBufferList,
															sizeof(AudioBufferList),
															NULL,
															NULL,
															kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
															&blockBuffer
															);
	if(err){
		NSLog(@"%d error", __LINE__);
	}
	
//	const AudioStreamPacketDescription	*packetDescs;
//	size_t numPacketDescs;
// 	CMSampleBufferGetAudioStreamPacketDescriptionsPtr(
//													  sampleBuffer,
//													  &packetDescs,
//													  &numPacketDescs);
	//NSLog(@"numPacketDescs: %d", (int)numPacketDescs);

	for (NSUInteger i = 0; i < audioBufferList.mNumberBuffers; i++) {
		AudioBuffer audioBuffer = audioBufferList.mBuffers[i];
		
		AudioQueueBufferRef buffer;
		err = AudioQueueAllocateBuffer(_queue, audioBuffer.mDataByteSize, &buffer);
		if(err){
			NSLog(@"%d error", __LINE__);
			break;
		}
		buffer->mAudioDataByteSize = audioBuffer.mDataByteSize;
		memcpy(buffer->mAudioData, audioBuffer.mData, audioBuffer.mDataByteSize);

		err = AudioQueueEnqueueBuffer(_queue, buffer, 0, NULL);
		if(err){
			NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain
												 code:err
											 userInfo:nil];
			NSLog(@"AudioQueueEnqueueBuffer error: %d %@", err, [error description]);
			break;
		}
		_buffering_count ++;
		//NSLog(@"add AudioBuffer");
	}
	if(!_playing && _buffering_count >= 2){
		_playing = YES;
		
		err = AudioQueueStart(_queue, NULL);
		if(err){
			NSLog(@"%d error", __LINE__);
		}else{
			NSLog(@"AQ started");
		}
	}
	
	CFRelease(blockBuffer);
	CFRelease(sampleBuffer);
}


@end
