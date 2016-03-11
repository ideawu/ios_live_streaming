//
//  AACCodec.m
//  irtc
//
//  Created by ideawu on 3/11/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "AACCodec.h"

@interface AACCodec(){
	
	BOOL _running;
	NSCondition *_condition;
	
	NSMutableArray *_samples;
	NSData *_processing_data;
	
	void (^_callback)(NSData *data, double duration);
}
@property (nonatomic) AudioStreamBasicDescription srcFormat;
@property (nonatomic) AudioStreamBasicDescription dstFormat;

@property (nonatomic) AudioConverterRef converter;
@property (nonatomic) uint8_t *aacBuffer;
@property (nonatomic) NSUInteger aacBufferSize;
@property (nonatomic) char *pcmBuffer;
@property (nonatomic) size_t pcmBufferSize;
@property (nonatomic) int sampleRate;
@property (nonatomic) int bitrate;
@property (nonatomic) dispatch_queue_t encoderQueue;
@end


@implementation AACCodec

- (id)init{
	self = [super init];
	
	_sampleRate = 22050;
	if(_sampleRate >= 44100){
		_bitrate = 192000; // 192kbs
	}else if(_sampleRate < 22000){
		_bitrate = 32000; // 32kbs
	}else{
		_bitrate = 64000; // 64kbs
	}
	
	_pcmBufferSize = 0;
	_pcmBuffer = NULL;
	
	_aacBufferSize = 8192;
	_aacBuffer = (uint8_t *)malloc(_aacBufferSize * sizeof(uint8_t));
	memset(_aacBuffer, 0, _aacBufferSize);
	
	_converter = NULL;
	
	_condition = [[NSCondition alloc] init];
	_samples = [[NSMutableArray alloc] init];
	
	memset(&_srcFormat, 0, sizeof(AudioStreamBasicDescription));
	memset(&_dstFormat, 0, sizeof(AudioStreamBasicDescription));
	
	return self;
}

- (void)start:(void (^)(NSData *data, double duration))callback{
	_callback = callback;
	_running = YES;
	[self performSelectorInBackground:@selector(run) withObject:nil];
}

- (void)shutdown{
	_running = NO;
	[_condition lock];
	[_condition broadcast];
	[_condition unlock];
}

- (void)dealloc{
	if(_converter){
		AudioConverterDispose(_converter);
	}
	if(_aacBuffer){
		free(_aacBuffer);
	}
}

- (void)setupCodecWithFormat:(AudioStreamBasicDescription)srcFormat dstFormat:(AudioStreamBasicDescription)dstFormat{
	_srcFormat = srcFormat;
	_dstFormat = dstFormat;
	[self createConverter];
}

- (void)setupCodecFromSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	OSStatus err;
	UInt32 size;
	_srcFormat = *CMAudioFormatDescriptionGetStreamBasicDescription((CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer));
	
	// kAudioFormatMPEG4AAC_HE does not work. Can't find `AudioClassDescription`. `mFormatFlags` is set to 0.
	_dstFormat.mFormatID = kAudioFormatMPEG4AAC;
	_dstFormat.mChannelsPerFrame = _srcFormat.mChannelsPerFrame;
	// 如果设置 bitrate, 应该让编码器自己决定 samplerate
	//	if(_bitrate > 0){
	//		_format.mSampleRate = 0;
	//	}else{
	//		_format.mSampleRate = _srcFormat.mSampleRate;
	//	}
	_dstFormat.mSampleRate = _srcFormat.mSampleRate;
	//_format.mFramesPerPacket = 1024;
	// 不能设置
	//_format.mBitsPerChannel = 16;
	//_format.mBytesPerPacket = _format.mChannelsPerFrame * (_format.mBitsPerChannel / 8);
	
	// use AudioFormat API to fill out the rest of the description
	size = sizeof(_dstFormat);
	err = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &_dstFormat);
	if (err != 0) {
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		NSLog(@"line: %d, error: %@", __LINE__, error);
	}
	
	[self createConverter];
}

- (void)encodePCM:(NSData *)raw{
	[self appendData:raw];
}


- (void)decodeAAC:(NSData *)aac{
	[self appendData:aac];
}

- (void)appendData:(NSData *)data{
	[_condition lock];
	{
		[_samples addObject:data];
		//NSLog(@"signal _samples: %d", (int)_samples.count);
		[_condition signal];
	}
	[_condition unlock];
}

- (void)run{
	OSStatus status;
	NSError *error = nil;
	
	while(_running){
		AudioBufferList outAudioBufferList;
		outAudioBufferList.mNumberBuffers = 1;
		outAudioBufferList.mBuffers[0].mNumberChannels = _dstFormat.mChannelsPerFrame;
		outAudioBufferList.mBuffers[0].mDataByteSize = (UInt32)_aacBufferSize;
		outAudioBufferList.mBuffers[0].mData = _aacBuffer;
		
		UInt32 outPackets = 1;
		status = AudioConverterFillComplexBuffer(_converter,
												 inInputDataProc,
												 (__bridge void *)(self),
												 &outPackets,
												 &outAudioBufferList,
												 NULL);
		if(status != noErr){
			NSLog(@"dispose converter");
			AudioConverterDispose(_converter);
			_converter = NULL;
			_running = NO;
			continue;
		}
		int outFrames = _dstFormat.mFramesPerPacket * outPackets;
		NSLog(@"outPackets: %d, frames: %d", (int)outPackets, outFrames);
		
		if (status == 0) {
			NSData *data = [NSData dataWithBytes:outAudioBufferList.mBuffers[0].mData length:outAudioBufferList.mBuffers[0].mDataByteSize];
			
			// deal with data
			double duration = outFrames / _dstFormat.mSampleRate;
			//NSLog(@"AAC ready, pts: %f, duration: %f, bytes: %d", _pts, duration, (int)data.length);
			if(_callback){
				_callback(data, duration);
			}
		} else {
			error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
			NSLog(@"decode error: %@", error);
		}
	}
}

// AudioConverterComplexInputDataProc
static OSStatus inInputDataProc(AudioConverterRef inAudioConverter,
								UInt32 *ioNumberDataPackets,
								AudioBufferList *ioData,
								AudioStreamPacketDescription **outDataPacketDescription,
								void *inUserData){
	AACCodec *me = (__bridge AACCodec *)(inUserData);
	UInt32 requestedPackets = *ioNumberDataPackets;
	//NSLog(@"Number of packets requested: %d", (unsigned int)requestedPackets);
	int ret = [me copyData:ioData requestedPackets:requestedPackets];
	if(ret == -1){
		*ioNumberDataPackets = 0;
		return -1;
	}
	*ioNumberDataPackets = ret;
	//NSLog(@"Copied %d packets into ioData, requested: %d", ret, requestedPackets);
	return noErr;
}

- (int)copyData:(AudioBufferList*)ioData requestedPackets:(UInt32)requestedPackets{
	NSData *data = nil;
	
	[_condition lock];
	{
		if(_samples.count == 0){
			[_condition wait];
		}
		//NSLog(@"_samples %d", (int)_samples.count);
		data = _samples.firstObject;
		if(data){
			[_samples removeObjectAtIndex:0];
		}
	}
	[_condition unlock];
	
	if(!data || !_running){
		NSLog(@"copyData is signaled to exit");
		return 0;
	}
	
	_processing_data = data;
	ioData->mBuffers[0].mNumberChannels = _srcFormat.mChannelsPerFrame;
	ioData->mBuffers[0].mData = (void *)_processing_data.bytes;
	ioData->mBuffers[0].mDataByteSize = (UInt32)_processing_data.length;
	
	int ret = (int)_processing_data.length / _srcFormat.mBytesPerPacket;
	return ret;
	
	//	AudioStreamBasicDescription f = *CMAudioFormatDescriptionGetStreamBasicDescription((CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer));
	//	if(f.mBitsPerChannel != _srcFormat.mBitsPerChannel || f.mChannelsPerFrame != _srcFormat.mChannelsPerFrame || f.mSampleRate != _srcFormat.mSampleRate){
	//		CFRelease(sampleBuffer);
	//		NSLog(@"Sample format changed!");
	//		[self printFormat:_srcFormat name:@"old"];
	//		[self printFormat:f name:@"new"];
	//		return -1;
	//	}
}

- (void)printFormat:(AudioStreamBasicDescription)format name:(NSString *)name{
	NSLog(@"--- begin %@", name);
	NSLog(@"format.mSampleRate:       %f", format.mSampleRate);
	NSLog(@"format.mBitsPerChannel:   %d", format.mBitsPerChannel);
	NSLog(@"format.mChannelsPerFrame: %d", format.mChannelsPerFrame);
	NSLog(@"format.mBytesPerFrame:    %d", format.mBytesPerFrame);
	NSLog(@"format.mFramesPerPacket:  %d", format.mFramesPerPacket);
	NSLog(@"format.mBytesPerPacket:   %d", format.mBytesPerPacket);
	NSLog(@"--- end %@", name);
}

- (void)createConverter{
	/*
	 http://stackoverflow.com/questions/12252791/understanding-remote-i-o-audiostreambasicdescription-asbd
	 注意, !kLinearPCMFormatFlagIsNonInterleaved(默认是 interleaved 的)
	 mBytesPerFrame != mChannelsPerFrame * mBitsPerChannel /8
	 */
	[self printFormat:_srcFormat name:@"src"];
	[self printFormat:_dstFormat name:@"dst"];
	
	//	AudioClassDescription *description = [self getAudioClassDescription];
	//	OSStatus status = AudioConverterNewSpecific(&_srcFormat,
	//												&_format,
	//												1, description,
	//												&_converter);
	OSStatus err;
	err = AudioConverterNew(&_srcFormat, &_dstFormat, &_converter);
	if (err != 0) {
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		NSLog(@"line: %d, error: %@", __LINE__, error);
		return;
	}
	if (_bitrate != 0) {
		UInt32 bitrate = (UInt32)_bitrate;
		UInt32 size = sizeof(bitrate);
		err = AudioConverterSetProperty(_converter, kAudioConverterEncodeBitRate, size, &bitrate);
		if (err != 0) {
			NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
			NSLog(@"line: %d, error: %@", __LINE__, error);
		}
		err = AudioConverterGetProperty(_converter, kAudioConverterEncodeBitRate, &size, &bitrate);
		if (err != 0) {
			NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
			NSLog(@"line: %d, error: %@", __LINE__, error);
		}else{
			NSLog(@"set bitrate: %d", bitrate);
		}
	}
}

@end
