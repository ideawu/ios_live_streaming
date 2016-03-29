//
//  AudioPlayer.m
//  VideoTest
//
//  Created by ideawu on 2/29/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "AudioPlayer.h"
#import <AudioToolbox/AudioToolbox.h>
#import "LockingQueue.h"

typedef enum{
	PlayerStateNone,
	PlayerStatePause,
	PlayerStateStop,
	PlayerStatePlaying,
}PlayerState;

#define kMaxBuffers  6

// AudioQueueSetParameter ( queue, kAudioQueueParam_Volume, gain )

@interface AudioPlayer(){
	BOOL _inited;
	PlayerState _state;
	AudioQueueBufferRef _silence;
	int _count;
	double _bitrate;
	
	LockingQueue *_freeBuffers;
}
@property AudioQueueRef queue;
@property AudioStreamBasicDescription format;
@property AudioStreamPacketDescription aspd;
@property (nonatomic) double bufferDuration;
@property (nonatomic) double maxBufferingTime;
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

	_maxBufferingTime = 0.2;

	_inited = NO;
	_state = PlayerStateNone;

	_format.mFormatID = kAudioFormatLinearPCM;
	_format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | kAudioFormatFlagIsBigEndian;
	_format.mChannelsPerFrame = 2;
	_format.mSampleRate = 44100;
	_format.mBitsPerChannel = 8 * _format.mChannelsPerFrame;
	_format.mFramesPerPacket = 1;
	_format.mBytesPerPacket = _format.mChannelsPerFrame * (_format.mBitsPerChannel / 8);
	_format.mBytesPerFrame = _format.mBytesPerPacket;
	_format.mReserved = 0;

	_silence = NULL;

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
	@synchronized(self){
		if(_queue){
			AudioQueueDispose(_queue, YES);
			_queue = NULL;
		}
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
	log_debug(@"format.mFormatFlags:      %d", (int)format.mFormatFlags);
	log_debug(@"format.mSampleRate:       %f", (double)format.mSampleRate);
	log_debug(@"format.mBitsPerChannel:   %d", (int)format.mBitsPerChannel);
	log_debug(@"format.mChannelsPerFrame: %d", (int)format.mChannelsPerFrame);
	log_debug(@"format.mBytesPerFrame:    %d", (int)format.mBytesPerFrame);
	log_debug(@"format.mFramesPerPacket:  %d", (int)format.mFramesPerPacket);
	log_debug(@"format.mBytesPerPacket:   %d", (int)format.mBytesPerPacket);
	log_debug(@"format.mReserved:         %d", (int)format.mReserved);
	log_debug(@"--- end %@", name);
}

- (void)setupAQ{
	log_debug(@"setup");
	if(_queue){
		[self stop];
	}
	
	if(_format.mBitsPerChannel > 0){
		_bitrate = _format.mSampleRate * _format.mChannelsPerFrame * _format.mBitsPerChannel;
	}else{
		_bitrate = _format.mSampleRate * _format.mChannelsPerFrame * 16;
	}
	_count = 0;
	_bufferDuration = 0;
	
	[self printFormat:_format name:@""];

	OSStatus err;
	err = AudioQueueNewOutput(&_format, callback, (__bridge void *)(self),
//							  CFRunLoopGetCurrent(), kCFRunLoopCommonModes,
							  NULL, NULL,
							  0, &_queue);
	if(err){
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		log_debug(@"line: %d, error: %@", __LINE__, error);
		return;
	}


	int bufferSize = [self computeRecordBufferSize:&_format duration:_maxBufferingTime];
	log_debug(@"bufferSize: %d, bitrate: %f, duration: %f", bufferSize, _bitrate, bufferSize/(_bitrate/8));
	
	_freeBuffers = [[LockingQueue alloc] initWithCapacity:kMaxBuffers];
	for(int i=0; i<kMaxBuffers; i++){
		AudioQueueBufferRef buffer;
		AudioQueueAllocateBufferWithPacketDescriptions(_queue, bufferSize, 32, &buffer);
		[_freeBuffers push:[NSValue valueWithPointer:buffer]];
	}

	err = AudioQueueAddPropertyListener(_queue, kAudioQueueProperty_IsRunning,
										isRunningProc, (__bridge void *)(self));
	if(err){
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		log_debug(@"%@", error);
	}

	log_debug(@"AQ setup");
}

- (int)computeRecordBufferSize:(AudioStreamBasicDescription *)format duration:(float)seconds{
	int packets, frames, bytes = 0;
	frames = (int)ceil(seconds * format->mSampleRate);

	if (format->mBytesPerFrame > 0){
		bytes = frames * format->mBytesPerFrame;
	}else {
		UInt32 maxPacketSize;
		if (format->mBytesPerPacket > 0){
			maxPacketSize = format->mBytesPerPacket;	// constant packet size
		}else {
			UInt32 propertySize = sizeof(maxPacketSize);
			AudioQueueGetProperty(_queue, kAudioQueueProperty_MaximumOutputPacketSize, &maxPacketSize,
								  &propertySize);
		}
		if (format->mFramesPerPacket > 0){
			packets = frames / format->mFramesPerPacket;
		}else{
			packets = frames;	// worst-case scenario: 1 frame in a packet
		}
		if (packets == 0){		// sanity check
			packets = 1;
		}
		log_debug(@"frames: %d packets: %d maxPacketSize: %d", frames, packets, (int)maxPacketSize);
		bytes = packets * maxPacketSize;
	}
	// ?
	bytes = MAX(bytes, 16 * 1024);
//	bytes = 8192;
	return bytes;
}

- (void)onCallback:(AudioQueueBufferRef)buffer{
	double duration = buffer->mAudioDataByteSize / (_bitrate/8);

	buffer->mAudioDataByteSize = 0;
	buffer->mPacketDescriptionCount = 0;
	[_freeBuffers push:[NSValue valueWithPointer:buffer]];

	@synchronized(self){
		_count --;
		_bufferDuration -= duration;
		log_debug(@"callback, buffers: %d, duration: %f", _count, _bufferDuration);

		if(_bufferDuration < 0.005){
			_bufferDuration = 0; // 消除浮点运算误差
			
			_state = PlayerStatePause;
			log_debug(@"AQ pause");
			AudioQueuePause(_queue);
			// 对于 AAC 不能调用 stop 只能 pause
			//AudioQueueStop(_queue, NO); // 不能在 callback 中调用 stop
		}
	}
}

static void isRunningProc (void *                     inUserData,
							  AudioQueueRef           inAQ,
							  AudioQueuePropertyID    inID)
{
	AudioPlayer *me = (__bridge AudioPlayer *)inUserData;
	[me onRunningProc];
}

- (void)onRunningProc{
	@synchronized(self){
		int isRunning;
		UInt32 size = sizeof(isRunning);
		OSStatus err = AudioQueueGetProperty(_queue, kAudioQueueProperty_IsRunning, &isRunning, &size);
		if(err){
			NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
			log_debug(@"AudioQueueEnqueueBuffer error: %d %@", (int)err, [error description]);
			return;
		}

		if(!isRunning){
			//_state = PlayerStateNone;
			_state = PlayerStateStop;
			_inited = NO;
		}
		log_debug(@"is %@", isRunning? @"running" : @"stopped");
	}
}

- (void)enqueueBuffer:(AudioQueueBufferRef)buffer{
	double duration = buffer->mAudioDataByteSize / (_bitrate/8);

	@synchronized(self){
		OSStatus err;
		if(_state == PlayerStateNone || _state == PlayerStatePlaying || _state == PlayerStatePause){
			err = AudioQueueEnqueueBuffer(_queue,
										  buffer,
										  buffer->mPacketDescriptionCount,
										  buffer->mPacketDescriptions);
			if(err){
				NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
				log_debug(@"AudioQueueEnqueueBuffer error: %d %@", (int)err, [error description]);
				return;
			}
			_count ++;
			_bufferDuration += duration;
			log_debug(@"enqueue, buffers: %d, duration: %f", _count, _bufferDuration);
		}

		if((_state == PlayerStateNone || _state == PlayerStatePause) && _bufferDuration > _maxBufferingTime){
			_state = PlayerStatePlaying;
			err = AudioQueueStart(_queue, NULL);
			if(err){
				NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
				log_debug(@"%d error %@", __LINE__, error);
			}else{
				log_debug(@"AQ started, buffers: %d, duration: %f", _count, _bufferDuration);
			}
		}
	}
}

- (void)appendData:(NSData *)data{
	@synchronized(self){
		if(!_inited){
			_inited = YES;
			_state = PlayerStateNone;
			[self setupAQ];
		}
	}

	AudioQueueBufferRef buffer;
	buffer = (AudioQueueBufferRef)([_freeBuffers.front pointerValue]);

	if(buffer->mAudioDataByteSize + data.length > buffer->mAudioDataBytesCapacity){
		[self enqueueBuffer:buffer];
		[_freeBuffers pop];
		buffer = (AudioQueueBufferRef)([_freeBuffers.front pointerValue]);
	}

	int offset = buffer->mAudioDataByteSize;
	buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mStartOffset = offset;
	buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mDataByteSize = (UInt32)data.length;
	memcpy(buffer->mAudioData + offset, data.bytes, data.length);
	buffer->mAudioDataByteSize += data.length;
	buffer->mPacketDescriptionCount ++;

	double duration = buffer->mAudioDataByteSize / (_bitrate/8);
	if(duration >= _maxBufferingTime/2 || buffer->mAudioDataByteSize == buffer->mAudioDataBytesCapacity){
		[self enqueueBuffer:buffer];
		[_freeBuffers pop];
	}
}


@end
