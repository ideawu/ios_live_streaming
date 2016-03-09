//
//  KFAACEncoder.m
//  Kickflip
//
//  Created by Christopher Ballinger on 12/18/13.
//  Copyright (c) 2013 Christopher Ballinger. All rights reserved.
//
//  http://stackoverflow.com/questions/10817036/can-i-use-avcapturesession-to-encode-an-aac-stream-to-memory

#import "AudioEncoder.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

@interface AudioEncoder(){
	void (^_callback)(NSData *data, double pts);
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

@implementation AudioEncoder

- (id)init{
	self = [super init];
	
	_sampleRate = 44100;
	_bitrate = 64 * 1024;

	_audioConverter = NULL;
	_pcmBufferSize = 0;
	_pcmBuffer = NULL;
	_aacBufferSize = 1024;
	_addADTSHeader = NO;

	_aacBuffer = malloc(_aacBufferSize * sizeof(uint8_t));
	memset(_aacBuffer, 0, _aacBufferSize);

	_encoderQueue = dispatch_queue_create("processQueue", DISPATCH_QUEUE_SERIAL);
	return self;
}

- (void)encodeWithBlock:(void (^)(NSData *data, double pts))callback{
	_callback = callback;
}

- (void)shutdown{
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
	AudioStreamBasicDescription inAudioStreamBasicDescription = *CMAudioFormatDescriptionGetStreamBasicDescription((CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer));
	
	AudioStreamBasicDescription outAudioStreamBasicDescription = {0};
	outAudioStreamBasicDescription.mSampleRate = _sampleRate;
	outAudioStreamBasicDescription.mFormatID = kAudioFormatMPEG4AAC; // kAudioFormatMPEG4AAC_HE does not work. Can't find `AudioClassDescription`. `mFormatFlags` is set to 0.
	outAudioStreamBasicDescription.mFormatFlags = kMPEG4Object_AAC_LC; // Format-specific flags to specify details of the format. Set to 0 to indicate no format flags. See “Audio Data Format Identifiers” for the flags that apply to each format.
	outAudioStreamBasicDescription.mBytesPerPacket = 0; // The number of bytes in a packet of audio data. To indicate variable packet size, set this field to 0. For a format that uses variable packet size, specify the size of each packet using an AudioStreamPacketDescription structure.
	outAudioStreamBasicDescription.mFramesPerPacket = 1024; // The number of frames in a packet of audio data. For uncompressed audio, the value is 1. For variable bit-rate formats, the value is a larger fixed number, such as 1024 for AAC. For formats with a variable number of frames per packet, such as Ogg Vorbis, set this field to 0.
	outAudioStreamBasicDescription.mBytesPerFrame = 0; // The number of bytes from the start of one frame to the start of the next frame in an audio buffer. Set this field to 0 for compressed formats. ...
	outAudioStreamBasicDescription.mChannelsPerFrame = 2;
	outAudioStreamBasicDescription.mBitsPerChannel = 0; // ... Set this field to 0 for compressed formats.
	outAudioStreamBasicDescription.mReserved = 0; // Pads the structure out to force an even 8-byte alignment. Must be set to 0.
	
	AudioClassDescription *description = [self getAudioClassDescription];

	OSStatus status = AudioConverterNewSpecific(&inAudioStreamBasicDescription,
												&outAudioStreamBasicDescription,
												1, description, &_audioConverter);
	if (status != 0) {
		NSLog(@"setup converter: %d", (int)status);
	}
	
	if (self.bitrate != 0) {
		UInt32 ulBitRate = (UInt32)self.bitrate;
		UInt32 ulSize = sizeof(ulBitRate);
		AudioConverterSetProperty(_audioConverter, kAudioConverterEncodeBitRate, ulSize, & ulBitRate);
	}
}

- (AudioClassDescription *)getAudioClassDescription{
	static AudioClassDescription desc;
	
	UInt32 type = kAudioFormatMPEG4AAC;
	UInt32 encoderSpecifier = type;
	UInt32 manufacturer = 0;//kAppleSoftwareAudioCodecManufacturer;
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
		if ((type == descriptions[i].mSubType) && (manufacturer == descriptions[i].mManufacturer)) {
			memcpy(&desc, &(descriptions[i]), sizeof(desc));
			return &desc;
		}
	}
	NSLog(@"error getting AudioClassDescription");
	return nil;
}

static OSStatus inInputDataProc(AudioConverterRef inAudioConverter,
								UInt32 *ioNumberDataPackets,
								AudioBufferList *ioData,
								AudioStreamPacketDescription **outDataPacketDescription,
								void *inUserData){
	AudioEncoder *encoder = (__bridge AudioEncoder *)(inUserData);
	UInt32 requestedPackets = *ioNumberDataPackets;
	//NSLog(@"Number of packets requested: %d", (unsigned int)requestedPackets);
	size_t copiedSamples = [encoder copyPCMSamplesIntoBuffer:ioData];
	if (copiedSamples < requestedPackets) {
		//NSLog(@"PCM buffer isn't full enough!");
		*ioNumberDataPackets = 0;
		return -1;
	}
	*ioNumberDataPackets = 1;
	//NSLog(@"Copied %zu samples into ioData", copiedSamples);
	return noErr;
}

- (size_t)copyPCMSamplesIntoBuffer:(AudioBufferList*)ioData {
	size_t originalBufferSize = _pcmBufferSize;
	if (!originalBufferSize) {
		return 0;
	}
	ioData->mBuffers[0].mData = _pcmBuffer;
	ioData->mBuffers[0].mDataByteSize = (UInt32)_pcmBufferSize;
	_pcmBuffer = NULL;
	_pcmBufferSize = 0;
	return originalBufferSize;
}

- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	CFRetain(sampleBuffer);
	dispatch_async(self.encoderQueue, ^{
		if (!_audioConverter) {
			[self setupAACEncoderFromSampleBuffer:sampleBuffer];
		}
		CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
		CFRetain(blockBuffer);
		OSStatus status = CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &_pcmBufferSize, &_pcmBuffer);
		NSError *error = nil;
		if (status != kCMBlockBufferNoErr) {
			error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		}
		//NSLog(@"PCM Buffer Size: %zu", _pcmBufferSize);
		
		memset(_aacBuffer, 0, _aacBufferSize);
		AudioBufferList outAudioBufferList = {0};
		outAudioBufferList.mNumberBuffers = 1;
		outAudioBufferList.mBuffers[0].mNumberChannels = 1;
		outAudioBufferList.mBuffers[0].mDataByteSize = (UInt32)_aacBufferSize;
		outAudioBufferList.mBuffers[0].mData = _aacBuffer;
		AudioStreamPacketDescription *outPacketDescription = NULL;
		UInt32 ioOutputDataPacketSize = 1;
		status = AudioConverterFillComplexBuffer(_audioConverter,
												 inInputDataProc,
												 (__bridge void *)(self),
												 &ioOutputDataPacketSize,
												 &outAudioBufferList,
												 outPacketDescription);
		NSLog(@"ioOutputDataPacketSize: %d", (unsigned int)ioOutputDataPacketSize);

		NSData *data = nil;
		if (status == 0) {
			NSData *rawAAC = [NSData dataWithBytes:outAudioBufferList.mBuffers[0].mData length:outAudioBufferList.mBuffers[0].mDataByteSize];
			if (_addADTSHeader) {
				NSData *adtsHeader = [self adtsDataForPacketLength:rawAAC.length];
				NSMutableData *fullData = [NSMutableData dataWithData:adtsHeader];
				[fullData appendData:rawAAC];
				data = fullData;
			} else {
				data = rawAAC;
			}
			
			// deal with data
			double pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
			if(_callback){
				_callback(data, pts);
			}
		} else {
			error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
			NSLog(@"%@", error);
		}
		
		CFRelease(sampleBuffer);
		CFRelease(blockBuffer);
   });
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
