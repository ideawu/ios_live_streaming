//
//  AudioPlayer.m
//  VideoTest
//
//  Created by ideawu on 2/29/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "AudioPlayer.h"
#import <AudioToolbox/AudioToolbox.h>


static void callback(void *custom_data, AudioQueueRef queue, AudioQueueBufferRef buffer){
	AudioQueueFreeBuffer(queue, buffer);
	NSLog(@"callback");
}


@interface AudioPlayer(){
	AudioQueueRef _queue;
	BOOL _started;
}
@property (assign, nonatomic) AudioStreamPacketDescription *packetDescriptions;
@property (assign, nonatomic) UInt32 numberOfPacketDescriptions;
@end


@implementation AudioPlayer

- (id)init{
	self = [super init];
	
	_started = NO;
	
	self.packetDescriptions = malloc(sizeof(AudioStreamPacketDescription) * 512);
	self.numberOfPacketDescriptions = 0;

	return self;
}

- (void)stop{
	AudioQueueStop(_queue, false);
	AudioQueueDispose(_queue, false);
}

- (void)appendSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	if(!_started){
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
		
		AudioStreamBasicDescription format = *CMAudioFormatDescriptionGetStreamBasicDescription((CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer));
		NSLog(@"format.mSampleRate:      %f", format.mSampleRate);
		NSLog(@"format.mBitsPerChannel:  %d", format.mBitsPerChannel);
		NSLog(@"mChannelsPerFrame:       %d", format.mChannelsPerFrame);
		NSLog(@"format.mBytesPerFrame:   %d", format.mBytesPerFrame);
		NSLog(@"format.mFramesPerPacket: %d", format.mFramesPerPacket);
		NSLog(@"format.mBytesPerPacket:  %d", format.mBytesPerPacket);
		
		OSStatus err;
		err = AudioQueueNewOutput(&format, callback, NULL, NULL, NULL, 0, &_queue);
		if(err){
			NSLog(@"%d error", __LINE__);
		}
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
	
	const AudioStreamPacketDescription	*packetDescs;
	size_t numPacketDescs;
 	CMSampleBufferGetAudioStreamPacketDescriptionsPtr(
													  sampleBuffer,
													  &packetDescs,
													  &numPacketDescs);
	//NSLog(@"numPacketDescs: %d", (int)numPacketDescs);

	for (NSUInteger i = 0; i < audioBufferList.mNumberBuffers; i++) {
		AudioBuffer audioBuffer = audioBufferList.mBuffers[i];
		
		AudioQueueBufferRef buffer;
		err = AudioQueueAllocateBuffer(_queue, audioBuffer.mDataByteSize, &buffer);
		if(err){
			NSLog(@"%d error", __LINE__);
			break;
		}
		memcpy(buffer->mAudioData, audioBuffer.mData, audioBuffer.mDataByteSize);
		buffer->mAudioDataByteSize = audioBuffer.mDataByteSize;
		err = AudioQueueEnqueueBuffer(_queue, buffer, (UInt32)numPacketDescs, packetDescs);
		if(err){
			NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain
												 code:err
											 userInfo:nil];
			NSLog(@"AudioQueueEnqueueBuffer error: %d %@", err, [error description]);
			break;
		}
		//NSLog(@"add AudioBuffer");
	}
	if(!_started){
		_started = YES;
		err = AudioQueueStart(_queue, NULL);
		if(err){
			NSLog(@"%d error", __LINE__);
		}
	}
	
	CFRelease(blockBuffer);
	CFRelease(sampleBuffer);
}


@end
