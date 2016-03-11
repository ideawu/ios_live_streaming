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

@property (nonatomic) AudioConverterRef converter;
@property (nonatomic) int sampleRate;
@property (nonatomic) int bitrate;

@property AudioStreamPacketDescription aspd;
@end


@implementation AACCodec

- (id)init{
	self = [super init];
	
	// if encoding to AAC set the bitrate
	// kAudioConverterEncodeBitRate is a UInt32 value containing the number of bits per second to aim for when encoding data
	// when you explicitly set the bit rate and the sample rate, this tells the encoder to stick with both bit rate and sample rate
	//     but there are combinations (also depending on the number of channels) which will not be allowed
	// if you do not explicitly set a bit rate the encoder will pick the correct value for you depending on samplerate and number of channels
	// bit rate also scales with the number of channels, therefore one bit rate per sample rate can be used for mono cases
	//    and if you have stereo or more, you can multiply that number by the number of channels.
	_sampleRate = 22050;
	if(_sampleRate >= 44100){
		_bitrate = 192000; // 192kbs
	}else if(_sampleRate < 22000){
		_bitrate = 32000; // 32kbs
	}else{
		_bitrate = 64000; // 64kbs
	}

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
		log_debug(@"line: %d, error: %@", __LINE__, error);
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
		//log_debug(@"signal _samples: %d", (int)_samples.count);
		[_condition signal];
	}
	[_condition unlock];
}

- (void)run{
	OSStatus err;
	
	uint8_t *_aacBuffer;
	NSUInteger _aacBufferSize;
	_aacBufferSize = 8192;
	_aacBuffer = (uint8_t *)malloc(_aacBufferSize * sizeof(uint8_t));
	memset(_aacBuffer, 0, _aacBufferSize);
	
	while(_running){
		AudioBufferList outAudioBufferList;
		outAudioBufferList.mNumberBuffers = 1;
		outAudioBufferList.mBuffers[0].mNumberChannels = _dstFormat.mChannelsPerFrame;
		outAudioBufferList.mBuffers[0].mDataByteSize = (UInt32)_aacBufferSize;
		outAudioBufferList.mBuffers[0].mData = _aacBuffer;

		UInt32 outPackets;
		if(_srcFormat.mFormatID == kAudioFormatLinearPCM){
			outPackets = 1;
			err = AudioConverterFillComplexBuffer(_converter,
												  inInputDataProc,
												  (__bridge void *)(self),
												  &outPackets,
												  &outAudioBufferList,
												  NULL);
		}else{
			outPackets = 1024 / _dstFormat.mFramesPerPacket;
			AudioStreamPacketDescription outPacketDescs[outPackets];
			err = AudioConverterFillComplexBuffer(_converter,
												  inInputDataProc,
												  (__bridge void *)(self),
												  &outPackets,
												  &outAudioBufferList,
												  outPacketDescs);
		}
		if(err != noErr || outPackets == 0){
			if(err){
				NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
				log_debug(@"AudioConverterFillComplexBuffer error: %@", error);
			}
			log_debug(@"dispose converter");
			AudioConverterDispose(_converter);
			_converter = NULL;
			_running = NO;
			continue;
		}

		int outFrames = _dstFormat.mFramesPerPacket * outPackets;
		int outBytes = outAudioBufferList.mBuffers[0].mDataByteSize;
//		log_debug(@"outPackets: %d, frames: %d, %d bytes", (int)outPackets, outFrames, outBytes);

		if (err == 0) {
			NSData *data = [NSData dataWithBytes:outAudioBufferList.mBuffers[0].mData length:outBytes];
			
			// deal with data
			double duration = outFrames / _dstFormat.mSampleRate;
			//log_debug(@"AAC ready, pts: %f, duration: %f, bytes: %d", _pts, duration, (int)data.length);
			if(_callback){
				_callback(data, duration);
			}
		} else {
			NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
			log_debug(@"%d error: %@", __LINE__, error);
		}
	}
	
	free(_aacBuffer);
}

// AudioConverterComplexInputDataProc
static OSStatus inInputDataProc(AudioConverterRef inAudioConverter,
								UInt32 *ioNumberDataPackets,
								AudioBufferList *ioData,
								AudioStreamPacketDescription **outDataPacketDescription,
								void *inUserData){
	AACCodec *me = (__bridge AACCodec *)(inUserData);
	UInt32 requestedPackets = *ioNumberDataPackets;
//	log_debug(@"Number of packets requested: %d", (unsigned int)requestedPackets);
	int ret = [me copyData:ioData requestedPackets:requestedPackets aspd:outDataPacketDescription];
	if(ret == -1){
		*ioNumberDataPackets = 0;
		return -1;
	}
	*ioNumberDataPackets = ret;
//	log_debug(@"Copied %d packets into ioData, requested: %d", ret, requestedPackets);
	return noErr;
}

- (int)copyData:(AudioBufferList*)ioData requestedPackets:(UInt32)requestedPackets aspd:(AudioStreamPacketDescription**)aspd{
	NSData *data = nil;
	
	[_condition lock];
	{
		if(_samples.count == 0){
			[_condition wait];
		}
		//log_debug(@"_samples %d", (int)_samples.count);
		data = _samples.firstObject;
		if(data){
			[_samples removeObjectAtIndex:0];
		}
	}
	[_condition unlock];
	
	if(!data || !_running){
		log_debug(@"copyData is signaled to exit");
		return 0;
	}
	
	_processing_data = data;
	ioData->mBuffers[0].mNumberChannels = _srcFormat.mChannelsPerFrame;
	ioData->mBuffers[0].mData = (void *)_processing_data.bytes;
	ioData->mBuffers[0].mDataByteSize = (UInt32)_processing_data.length;

	// PCM => AAC 时启用
	if(aspd && requestedPackets == 1){
		_aspd.mStartOffset = 0;
		_aspd.mDataByteSize = (UInt32)_processing_data.length;
		_aspd.mVariableFramesInPacket = requestedPackets;
		*aspd = &_aspd;
	}
	
	if(_srcFormat.mFormatID == kAudioFormatMPEG4AAC){
		return requestedPackets;
	}

	int ret = (int)_processing_data.length / _srcFormat.mBytesPerPacket;
	return ret;
	
	//	AudioStreamBasicDescription f = *CMAudioFormatDescriptionGetStreamBasicDescription((CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer));
	//	if(f.mBitsPerChannel != _srcFormat.mBitsPerChannel || f.mChannelsPerFrame != _srcFormat.mChannelsPerFrame || f.mSampleRate != _srcFormat.mSampleRate){
	//		CFRelease(sampleBuffer);
	//		log_debug(@"Sample format changed!");
	//		[self printFormat:_srcFormat name:@"old"];
	//		[self printFormat:f name:@"new"];
	//		return -1;
	//	}
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

- (void)createConverter{
	/*
	 http://stackoverflow.com/questions/12252791/understanding-remote-i-o-audiostreambasicdescription-asbd
	 注意, !kLinearPCMFormatFlagIsNonInterleaved(默认是 interleaved 的)
	 mBytesPerFrame != mChannelsPerFrame * mBitsPerChannel /8
	 */
	// 似乎对 kAudioFormatMPEG4AAC, 不能指定下面的属性
	if(_srcFormat.mFormatID == kAudioFormatMPEG4AAC){
		_srcFormat.mBitsPerChannel = 0;
		_srcFormat.mBytesPerFrame = 0;
		_srcFormat.mBytesPerPacket = 0;
	}
	if(_dstFormat.mFormatID == kAudioFormatMPEG4AAC){
		_dstFormat.mBitsPerChannel = 0;
		_dstFormat.mBytesPerFrame = 0;
		_dstFormat.mBytesPerPacket = 0;
	}
	// PCM 不指定 bitrate
	if(_dstFormat.mFormatID == kAudioFormatLinearPCM){
		_bitrate = 0;
	}

//	[self printFormat:_srcFormat name:@"src"];
//	[self printFormat:_dstFormat name:@"dst"];

	OSStatus err;
//	AudioClassDescription *description = [self getAudioClassDescription];
//	err = AudioConverterNewSpecific(&_srcFormat,
//												&_dstFormat,
//												1, description,
//												&_converter);
	err = AudioConverterNew(&_srcFormat, &_dstFormat, &_converter);
	if (err != 0) {
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		log_debug(@"line: %d, error: %@", __LINE__, error);
		return;
	}
	
	// 获取真正的 format
	UInt32 size = sizeof(_srcFormat);
	err = AudioConverterGetProperty(_converter, kAudioConverterCurrentInputStreamDescription, &size, &_srcFormat);
	if (err != 0) {
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		log_debug(@"line: %d, error: %@", __LINE__, error);
		return;
	}
	size = sizeof(_dstFormat);
	err = AudioConverterGetProperty(_converter, kAudioConverterCurrentOutputStreamDescription, &size, &_dstFormat);
	if (err != 0) {
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		log_debug(@"line: %d, error: %@", __LINE__, error);
		return;
	}
	
	if (_bitrate != 0) {
		UInt32 bitrate = (UInt32)_bitrate;
		UInt32 size = sizeof(bitrate);
		err = AudioConverterSetProperty(_converter, kAudioConverterEncodeBitRate, size, &bitrate);
		if (err != 0) {
			NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
			log_debug(@"line: %d, error: %@", __LINE__, error);
		}
		err = AudioConverterGetProperty(_converter, kAudioConverterEncodeBitRate, &size, &bitrate);
		if (err != 0) {
			NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
			log_debug(@"line: %d, error: %@", __LINE__, error);
		}else{
			log_debug(@"set bitrate: %d", bitrate);
		}
	}

//	[self printFormat:_srcFormat name:@"src"];
//	[self printFormat:_dstFormat name:@"dst"];

	// 创建 AAC converter 的时候不能指定, 所以这里要补充回来
	if(_srcFormat.mBytesPerPacket == 0){
		_srcFormat.mBitsPerChannel = _srcFormat.mChannelsPerFrame * 8;
		_srcFormat.mBytesPerPacket = _srcFormat.mChannelsPerFrame * 2;
		_srcFormat.mBytesPerFrame = _srcFormat.mBytesPerPacket;
	}
	if(_dstFormat.mBytesPerPacket == 0){
		_dstFormat.mBitsPerChannel = _dstFormat.mChannelsPerFrame * 8;
		_dstFormat.mBytesPerPacket = _dstFormat.mChannelsPerFrame * 2;
		_dstFormat.mBytesPerFrame = _dstFormat.mBytesPerPacket;
	}
}

- (AudioClassDescription *)getAudioClassDescription{
	UInt32 type = kAudioFormatMPEG4AAC;
	UInt32 encoderSpecifier = type;
	OSStatus st;
	
	UInt32 size;
	st = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders,
									sizeof(encoderSpecifier),
									&encoderSpecifier,
									&size);
	if (st) {
		log_debug(@"error getting audio format propery info: %d", (int)(st));
		return nil;
	}
	
	unsigned int count = size / sizeof(AudioClassDescription);
	AudioClassDescription descriptions[count];
	st = AudioFormatGetProperty(kAudioFormatProperty_Encoders,
								sizeof(encoderSpecifier),
								&encoderSpecifier,
								&size,
								descriptions);
	if (st) {
		log_debug(@"error getting audio format propery: %d", (int)(st));
		return nil;
	}
	for (unsigned int i = 0; i < count; i++) {
		log_debug(@"%d %d %d", descriptions[i].mType, descriptions[i].mSubType, descriptions[i].mManufacturer);
	}
	//	for (unsigned int i = 0; i < count; i++) {
	//		UInt32 manufacturer = kAppleSoftwareAudioCodecManufacturer;
	//		if((type == descriptions[i].mSubType) && (manufacturer == descriptions[i].mManufacturer)) {
	//			memcpy(&desc, &(descriptions[i]), sizeof(desc));
	//			return &desc;
	//		}
	//	}
	log_debug(@"error getting AudioClassDescription");
	return nil;
}




@end
