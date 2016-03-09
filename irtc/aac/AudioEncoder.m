//  http://stackoverflow.com/questions/10817036/can-i-use-avcapturesession-to-encode-an-aac-stream-to-memory

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "AudioEncoder.h"

@interface AudioEncoder(){
	AudioStreamBasicDescription _format;
	AudioStreamBasicDescription _srcFormat;

	BOOL _running;
	NSCondition *_condition;
	
	NSMutableData *_samples;
	NSData *_samples_processing;
	
	void (^_callback)(NSData *data, double pts);
	
	double _pts;
}
@property (nonatomic) AudioConverterRef audioConverter;
@property (nonatomic) uint8_t *aacBuffer;
@property (nonatomic) NSUInteger aacBufferSize;
@property (nonatomic) char *pcmBuffer;
@property (nonatomic) size_t pcmBufferSize;
@property (nonatomic) int sampleRate;
@property (nonatomic) int bitrate;
@property (nonatomic) dispatch_queue_t encoderQueue;
@end

//sampleRate = 44100;
//sampleRate = 22050;
//sampleRate = 8000;

@implementation AudioEncoder

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
	
	int bytes_per_second = _sampleRate * sizeof(short) * 2; // 2 channels

	_aacBufferSize = bytes_per_second;
	_aacBuffer = malloc(_aacBufferSize * sizeof(uint8_t));
	memset(_aacBuffer, 0, _aacBufferSize);
	
	_addADTSHeader = NO;

	_audioConverter = NULL;
	return self;
}

- (void)encodeWithBlock:(void (^)(NSData *data, double pts))callback{
	_callback = callback;
	
	_running = YES;
	_condition = [[NSCondition alloc] init];
	_samples = [[NSMutableData alloc] init];
}

- (void)shutdown{
	_running = NO;
	[_condition lock];
	[_condition signal];
	[_condition unlock];
}

- (void)dealloc{
	if(_audioConverter){
		AudioConverterDispose(_audioConverter);
	}
	if(_aacBuffer){
		free(_aacBuffer);
	}
}

- (void)setupAACEncoderFromSampleBuffer:(CMSampleBufferRef)sampleBuffer {
	UInt32 size;
	_srcFormat = *CMAudioFormatDescriptionGetStreamBasicDescription((CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer));
	
	//UInt32 real_bytesPerChannel = inFormat.mBitsPerChannel / inFormat.mChannelsPerFrame / 8;

	_format.mFormatID = kAudioFormatMPEG4AAC; // kAudioFormatMPEG4AAC_HE does not work. Can't find `AudioClassDescription`. `mFormatFlags` is set to 0.
	_format.mSampleRate = _sampleRate;
	_format.mChannelsPerFrame = 2;
//	//_format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
//	//_format.mFormatFlags = 0;
//	_format.mFormatFlags = kMPEG4Object_AAC_LC; // Format-specific flags to specify details of the format. Set to 0 to indicate no format flags. See “Audio Data Format Identifiers” for the flags that apply to each format.
//	//_format.mBitsPerChannel = inFormat.mBitsPerChannel;
//	_format.mBytesPerPacket = 0; // The number of bytes in a packet of audio data. To indicate variable packet size, set this field to 0. For a format that uses variable packet size, specify the size of each packet using an AudioStreamPacketDescription structure.
//	_format.mFramesPerPacket = 1024; // The number of frames in a packet of audio data. For uncompressed audio, the value is 1. For variable bit-rate formats, the value is a larger fixed number, such as 1024 for AAC. For formats with a variable number of frames per packet, such as Ogg Vorbis, set this field to 0.
//	_format.mBytesPerFrame = 0; // The number of bytes from the start of one frame to the start of the next frame in an audio buffer. Set this field to 0 for compressed formats. ...
//	_format.mBitsPerChannel = 0; // ... Set this field to 0 for compressed formats.
//	_format.mReserved = 0; // Pads the structure out to force an even 8-byte alignment. Must be set to 0.
	
	// use AudioFormat API to fill out the rest of the description
	size = sizeof(_format);
	AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &_format);
	
	/*
	 http://stackoverflow.com/questions/12252791/understanding-remote-i-o-audiostreambasicdescription-asbd
	 注意, !kLinearPCMFormatFlagIsNonInterleaved(默认是 interleaved 的)
	 mBytesPerFrame != mChannelsPerFrame * mBitsPerChannel /8
	 */
	NSLog(@"format.mSampleRate:       %f", _srcFormat.mSampleRate);
	NSLog(@"format.mChannelsPerFrame: %d", _srcFormat.mChannelsPerFrame);
	NSLog(@"format.mBitsPerChannel:   %d", _srcFormat.mBitsPerChannel);
	NSLog(@"format.mBytesPerFrame:    %d", _srcFormat.mBytesPerFrame);
	NSLog(@"format.mFramesPerPacket:  %d", _srcFormat.mFramesPerPacket);
	NSLog(@"format.mBytesPerPacket:   %d", _srcFormat.mBytesPerPacket);
	NSLog(@"---");
	NSLog(@"format.mSampleRate:       %f", _format.mSampleRate);
	NSLog(@"format.mChannelsPerFrame: %d", _format.mChannelsPerFrame);
	NSLog(@"format.mBitsPerChannel:   %d", _format.mBitsPerChannel);
	NSLog(@"format.mBytesPerFrame:    %d", _format.mBytesPerFrame);
	NSLog(@"format.mFramesPerPacket:  %d", _format.mFramesPerPacket);
	NSLog(@"format.mBytesPerPacket:   %d", _format.mBytesPerPacket);
	NSLog(@"---");

//	AudioClassDescription *description = [self getAudioClassDescription];
//	OSStatus status = AudioConverterNewSpecific(&_srcFormat,
//												&_format,
//												1, description,
//												&_audioConverter);
	OSStatus status = AudioConverterNew(&_srcFormat, &_format, &_audioConverter);
	if (status != 0) {
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		NSLog(@"setup converter error: %@", error);
	}

//	if (_format.mBytesPerPacket == 0) {
//		UInt32 outputSizePerPacket;
//		// if the destination format is VBR, we need to get max size per packet from the converter
//		size = sizeof(outputSizePerPacket);
//		AudioConverterGetProperty(_audioConverter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &outputSizePerPacket);
//		NSLog(@"wwwwwwww %d", outputSizePerPacket);
//		// allocate memory for the PacketDescription structures describing the layout of each packet
//		//outputPacketDescriptions = new AudioStreamPacketDescription [theOutputBufSize / outputSizePerPacket];
//	}
	
	if (self.bitrate != 0) {
		UInt32 bitrate = (UInt32)self.bitrate;
		UInt32 size = sizeof(bitrate);
		AudioConverterSetProperty(_audioConverter, kAudioConverterEncodeBitRate, size, &bitrate);
		AudioConverterGetProperty(_audioConverter, kAudioConverterEncodeBitRate, &size, &bitrate);
		NSLog(@"AAC Encode Bitrate: %d", (int)bitrate);
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
		NSLog(@"error getting audio format propery info: %d", (int)(st));
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
		NSLog(@"error getting audio format propery: %d", (int)(st));
		return nil;
	}
	for (unsigned int i = 0; i < count; i++) {
		NSLog(@"%d %d %d", descriptions[i].mType, descriptions[i].mSubType, descriptions[i].mManufacturer);
	}
//	for (unsigned int i = 0; i < count; i++) {
//		UInt32 manufacturer = kAppleSoftwareAudioCodecManufacturer;
//		if((type == descriptions[i].mSubType) && (manufacturer == descriptions[i].mManufacturer)) {
//			memcpy(&desc, &(descriptions[i]), sizeof(desc));
//			return &desc;
//		}
//	}
	NSLog(@"error getting AudioClassDescription");
	return nil;
}

// AudioConverterComplexInputDataProc
static OSStatus inInputDataProc(AudioConverterRef inAudioConverter,
								UInt32 *ioNumberDataPackets,
								AudioBufferList *ioData,
								AudioStreamPacketDescription **outDataPacketDescription,
								void *inUserData){
	AudioEncoder *encoder = (__bridge AudioEncoder *)(inUserData);
	UInt32 requestedPackets = *ioNumberDataPackets;
	//NSLog(@"Number of packets requested: %d", (unsigned int)requestedPackets);
	int ret = [encoder copyPCMSamplesIntoBuffer:ioData requestedPackets:requestedPackets];
	*ioNumberDataPackets = ret;
	NSLog(@"Copied %d packets into ioData, requested: %d", ret, requestedPackets);
	return noErr;
}

- (int)copyPCMSamplesIntoBuffer:(AudioBufferList*)ioData requestedPackets:(UInt32)requestedPackets{
	int expect = requestedPackets * _srcFormat.mBytesPerPacket;
	
	[_condition lock];
	{
		//while(_samples.length < expect){
		if(_samples.length == 0){
			[_condition wait];
		
			if(!_running){
				expect = 0;
				//break;
			}
		}
		_samples_processing = nil;
		if(_samples.length > 0){
			if(expect > _samples.length){
				expect = (int)_samples.length;
			}
			_samples_processing = [NSData dataWithBytes:_samples.bytes length:expect];
			[_samples replaceBytesInRange:NSMakeRange(0, _samples_processing.length) withBytes:NULL length:0];
		}
	}
	[_condition unlock];
	if(!_samples_processing){
		return 0;
	}
	
	if(!_running){
		NSLog(@"copyPCMSamplesIntoBuffer return 0");
		return 0;
	}
	
	ioData->mBuffers[0].mNumberChannels = _srcFormat.mChannelsPerFrame;
	ioData->mBuffers[0].mData = (void *)_samples_processing.bytes;
	ioData->mBuffers[0].mDataByteSize = (UInt32)_samples_processing.length;
	
	int ret = (int)_samples_processing.length / _srcFormat.mBytesPerPacket;
	return ret;
}

- (void)runUntilStop{
	while(_running){
		OSStatus status;
		NSError *error = nil;

		AudioBufferList outAudioBufferList;
		outAudioBufferList.mNumberBuffers = 1;
		outAudioBufferList.mBuffers[0].mNumberChannels = _format.mChannelsPerFrame;
		outAudioBufferList.mBuffers[0].mDataByteSize = (UInt32)_aacBufferSize;
		outAudioBufferList.mBuffers[0].mData = _aacBuffer;
		
		UInt32 ioOutputDataPacketSize = 1; // 越小, chunk的时间越短
		status = AudioConverterFillComplexBuffer(_audioConverter,
												 inInputDataProc,
												 (__bridge void *)(self),
												 &ioOutputDataPacketSize,
												 &outAudioBufferList,
												 NULL);
		//NSLog(@"ioOutputDataPacketSize: %d", (unsigned int)ioOutputDataPacketSize);
		
		if (status == 0) {
			NSData *data = [NSData dataWithBytes:outAudioBufferList.mBuffers[0].mData length:outAudioBufferList.mBuffers[0].mDataByteSize];
			if (_addADTSHeader) {
				NSData *adtsHeader = [self adtsDataForPacketLength:data.length];
				NSMutableData *fullData = [NSMutableData dataWithData:adtsHeader];
				[fullData appendData:data];
				data = fullData;
			}
			
			// deal with data
			double duration = (double)_format.mFramesPerPacket * ioOutputDataPacketSize / _format.mSampleRate;
			NSLog(@"AAC ready, pts: %f, duration: %f, bytes: %d", _pts, duration, (int)data.length);
			if(_callback){
				_callback(data, _pts);
			}
		} else {
			error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
			NSLog(@"decode error: %@", error);
		}
	}
}

- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	if(!_running){
		return;
	}
	
	if (!_audioConverter) {
		[self setupAACEncoderFromSampleBuffer:sampleBuffer];
		[self performSelectorInBackground:@selector(runUntilStop) withObject:nil];
	}
	_pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
	
	char *pcm;
	size_t size;
	CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
	OSStatus status = CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &size, &pcm);
	NSError *error = nil;
	if (status != kCMBlockBufferNoErr) {
		error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		NSLog(@"kCMBlockBuffer error: %@", error);
	}else{
		[_condition lock];
		{
			[_samples appendBytes:pcm length:size];
			//NSLog(@"signal %d", (int)_samples.length);
			[_condition signal];
		}
		[_condition unlock];
	}
}


/**
 *  Add ADTS header at the beginning of each and every AAC packet.
 *  This is needed as MediaCodec encoder generates a packet of raw
 *  AAC data.
 *
 *  Note the packetLen must count in the ADTS header itself.
 *  See: http://wiki.multimedia.cx/index.php?title=ADTS
 *  Also: http://wiki.multimedia.cx/index.php?title=MPEG-4_Audio#Channel_Configurations
 **/
- (NSData*) adtsDataForPacketLength:(NSUInteger)packetLength {
	int adtsLength = 7;
	char *packet = malloc(sizeof(char) * adtsLength);
	// Variables Recycled by addADTStoPacket
	int profile = 2;  //AAC LC
	//39=MediaCodecInfo.CodecProfileLevel.AACObjectELD;
	int freqIdx = 4;  //44.1KHz
	int chanCfg = 1;  //MPEG-4 Audio Channel Configuration. 1 Channel front-center
	NSUInteger fullLength = adtsLength + packetLength;
	// fill in ADTS data
	packet[0] = (char)0xFF;	// 11111111  	= syncword
	packet[1] = (char)0xF9;	// 1111 1 00 1  = syncword MPEG-2 Layer CRC
	packet[2] = (char)(((profile-1)<<6) + (freqIdx<<2) +(chanCfg>>2));
	packet[3] = (char)(((chanCfg&3)<<6) + (fullLength>>11));
	packet[4] = (char)((fullLength&0x7FF) >> 3);
	packet[5] = (char)(((fullLength&7)<<5) + 0x1F);
	packet[6] = (char)0xFC;
	NSData *data = [NSData dataWithBytesNoCopy:packet length:adtsLength freeWhenDone:YES];
	return data;
}


@end
