//
//  AudioBufferQueue.m
//  irtc
//
//  Created by ideawu on 16-3-12.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import "AudioBufferQueue.h"

@interface AudioBufferQueue(){
	AudioQueueRef _queue;

	NSCondition *_free_condition;
	NSCondition *_ready_condition;

	int _total;
	int _free_index;
	int _free_count;
	AudioQueueBufferRef *_free_items;
	int _ready_index;
	int _ready_count;
	AudioQueueBufferRef *_ready_items;
}
@end

@implementation AudioBufferQueue

- (id)initWithAudioQueue:(AudioQueueRef)queue{
	self = [super init];
	_queue = queue;
	_total = 3;

	_free_index = 0;
	_free_count = _total;
	_free_items = (AudioQueueBufferRef *)malloc(_total * sizeof(AudioQueueBufferRef));
	_free_condition = [[NSCondition alloc] init];

	_ready_index = 0;
	_ready_count = 0;
	_ready_items = (AudioQueueBufferRef *)malloc(_total * sizeof(AudioQueueBufferRef));
	_ready_condition = [[NSCondition alloc] init];

	for(int i=0; i<_total; i++){
		AudioQueueBufferRef buffer;
		OSStatus err = AudioQueueAllocateBufferWithPacketDescriptions(_queue, 16*1024, 32, &buffer);
		if(err){
			NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
			log_debug(@"error %@", error);
			exit(0);
		}
		_free_items[i] = buffer;
	}

	return self;
}

- (void)dealloc{
	for(int i=0; i<_total; i++){
		if(_free_items[i]){
			AudioQueueFreeBuffer(_queue, _free_items[i]);
		}
	}
	free(_free_items);
	free(_ready_items);
}

- (AudioQueueBufferRef)getFreeBuffer{
	AudioQueueBufferRef buffer;
	[_free_condition lock];
	{
		while(_free_count == 0){
			[_free_condition wait];
		}

		buffer = _free_items[_free_index];
	}
	[_free_condition unlock];
	return buffer;
}

- (void)pushFreeBuffer{
	[_free_condition lock];
	{
		while(_free_count == _total){
			[_free_condition wait];
		}

		_free_count ++;
		[_free_condition signal];
	}
	[_free_condition unlock];
}

- (AudioQueueBufferRef)popFreeBuffer{
	AudioQueueBufferRef buffer;
	[_free_condition lock];
	{
		while(_free_count == 0){
			[_free_condition wait];
		}

		buffer = _free_items[_free_index];
		if(++_free_index >= _total){
			_free_index = 0;
		}
		_free_count --;
	}
	[_free_condition unlock];
	return buffer;
}

- (int)freeCount{
	return _free_count;
}

- (int)readyCount{
	int ret;
	[_ready_condition lock];
	ret = _ready_count;
	[_ready_condition unlock];
	return ret;
}


- (void)pushReadyBuffer:(AudioQueueBufferRef)buffer{
	[_ready_condition lock];
	{
		while(_ready_count == _total){
			[_ready_condition wait];
		}

		int index = (_ready_index + _ready_count) % _total;
		_ready_items[index] = buffer;
		_ready_count ++;
		[_ready_condition signal];
	}
	[_ready_condition unlock];
}

- (AudioQueueBufferRef)popReadyBuffer{
	AudioQueueBufferRef buffer;
	[_ready_condition lock];
	{
		while(_ready_count == 0){
			[_ready_condition wait];
		}

		buffer = _ready_items[_ready_index];
		if(++_ready_index >= _total){
			_ready_index = 0;
		}
		_ready_count --;
	}
	[_ready_condition unlock];
	return buffer;
}

@end
