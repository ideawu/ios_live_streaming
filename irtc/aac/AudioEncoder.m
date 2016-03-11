//  http://stackoverflow.com/questions/10817036/can-i-use-avcapturesession-to-encode-an-aac-stream-to-memory

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "AudioEncoder.h"
#import "AACCodec.h"

@interface AudioEncoder(){
	AudioStreamBasicDescription _format;
	AudioStreamBasicDescription _srcFormat;

	BOOL _running;
	void (^_callback)(NSData *aac, double duration);
	
	double _pts;
}
@property AACCodec *codec;
@end

@implementation AudioEncoder

- (id)init{
	self = [super init];
	return self;
}

- (void)start:(void (^)(NSData *aac, double duration))callback{
	_callback = callback;
}

- (void)shutdown{
	if(_codec){
		[_codec shutdown];
	}
}

- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	if(!_codec){
		_codec = [[AACCodec alloc] init];
		[_codec setupCodecFromSampleBuffer:sampleBuffer];
		[_codec start:_callback];
	}
	
	NSData *raw = [self sampleBufferToData:sampleBuffer];
	if(!raw){
		return;
	}
	[_codec encodePCM:raw];
}

- (NSData *)sampleBufferToData:(CMSampleBufferRef)sampleBuffer{
	char *pcm;
	size_t size;
	CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
	OSStatus status = CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &size, &pcm);
	NSError *error = nil;
	if (status != kCMBlockBufferNoErr) {
		error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		NSLog(@"kCMBlockBuffer error: %@", error);
		return nil;
	}
	return [NSData dataWithBytes:pcm length:size];
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
	char *packet = (char *)malloc(sizeof(char) * adtsLength);
	memset(packet, 0, adtsLength);
	// Variables Recycled by addADTStoPacket
	int profile = 2;  //AAC LC
	//39=MediaCodecInfo.CodecProfileLevel.AACObjectELD;
	int freqIdx = 4;  //44.1KHz
	if(_format.mSampleRate == 96000){
		freqIdx = 0;
	}else if(_format.mSampleRate == 88200){
		freqIdx = 1;
	}else if(_format.mSampleRate == 64000){
		freqIdx = 2;
	}else if(_format.mSampleRate == 48000){
		freqIdx = 3;
	}else if(_format.mSampleRate == 44100){
		freqIdx = 4;
	}else if(_format.mSampleRate == 32000){
		freqIdx = 5;
	}else if(_format.mSampleRate == 22050){
		freqIdx = 6;
	}else if(_format.mSampleRate == 16000){
		freqIdx = 7;
	}else if(_format.mSampleRate == 12000){
		freqIdx = 8;
	}else if(_format.mSampleRate == 11025){
		freqIdx = 9;
	}else if(_format.mSampleRate == 8000){
		freqIdx = 10;
	}else if(_format.mSampleRate == 7350){
		freqIdx = 11;
	}
	int chanCfg = _format.mChannelsPerFrame;  //MPEG-4 Audio Channel Configuration.
	UInt16 fullLength = adtsLength + packetLength; // 13 bit
	// fill in ADTS data
	packet[0] |= (char)0xFF; // 8 bits syncword
	//
	packet[1] |= (char)0xf0; // 4 bits syncword
	packet[1] |= 0 << 3;     // 1 bits ID, '0': MPEG-4, '1': MPEG-2
	packet[1] |= 0 << 2;     // 2 bits layer, always '00'
	packet[1] |= 1 << 0;     // 1 bit protection_absent
	//
	packet[2] |= (profile - 1) << 6;     // 2 bits profile
	packet[2] |= (freqIdx & 0xf) << 2;   // 4 bits sample index
	packet[2] |= 0 << 1;                 // 1 bits private
	packet[2] |= (chanCfg & 0x4) >> 2;   // 1 bits channel
	//
	packet[3] |= (chanCfg & 0x3) << 6;      // 2 bits channel
	packet[3] |= 0;                         // 1 bits oringal
	packet[3] |= 0;                         // 1 bits home
	packet[3] |= 0;                         // 1 bits copyright
	packet[3] |= 0;                         // 1 bits copyright
	packet[3] |= (fullLength >> 11) & 0x3;  // 2 bits length
	//
	packet[4] |= (fullLength >> 3)  & 0xff; // 8 bits length
	packet[5] |= (fullLength & 0x7) << 5;   // 3 bits length
	packet[5] |= 0x1f;                      // 5 bits fullness
	//
	packet[6] |= 0xfc; // 6 bits fullness + 2 bits
	NSData *data = [NSData dataWithBytesNoCopy:packet length:adtsLength freeWhenDone:YES];
	return data;
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


@end

/*
AudioEncoder *encoder = [[AudioEncoder alloc] init];
[encoder encodeWithBlock:^(NSData *data, double pts, double duration) {
	NSLog(@"%d bytes, %f %f", (int)data.length, pts, duration);
}];

NSString *input = [NSTemporaryDirectory() stringByAppendingFormat:@"/a.aif"];
AudioReader *reader = [AudioReader readerWithFile:input];
CMSampleBufferRef sampleBuffer;
while(1){
	sampleBuffer = [reader nextSampleBuffer];
	if(!sampleBuffer){
		break;
	}
	
	[encoder encodeSampleBuffer:sampleBuffer];
	
	CFRelease(sampleBuffer);
}
NSLog(@"end");
sleep(1);
*/
