//  http://stackoverflow.com/questions/10817036/can-i-use-avcapturesession-to-encode-an-aac-stream-to-memory

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "AudioEncoder.h"
#import "AACCodec.h"

@interface AudioEncoder(){
	void (^_callback)(NSData *aac, double pts, double duration);
	double _pts;
	double _prev_pts;
	double _prev_duration;
	double _sync_pts;
}
@property AACCodec *codec;
@end

@implementation AudioEncoder

- (id)init{
	self = [super init];
	_pts = 0;
	_prev_pts = 0;
	return self;
}

- (void)start:(void (^)(NSData *aac, double pts, double duration))callback{
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
		[_codec start:^(NSData *aac, double duration) {
//			NSData *adts = [self adtsDataForPacketLength:aac.length];
//			NSMutableData *full = [[NSMutableData alloc] init];
//			[full appendData:adts];
//			[full appendData:aac];
//			aac = full;
			double pts;
			@synchronized(self){
				pts = _pts;
				_pts += duration;
			}
			_callback(aac, pts, duration);
		}];
		_pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
	}

	BOOL drop = NO;

	double pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
	double duration = CMTimeGetSeconds(CMSampleBufferGetDuration(sampleBuffer));
	if(_pts == 0){
		_pts = pts;
	}else{
		double expect_pts = _prev_pts + _prev_duration;
		double diff = pts - expect_pts;
		@synchronized(self){
			// 如果录制设备原始视频丢包, 需要对累积时间进行修复
			_pts += diff;
			double encoder_delay = pts - _pts;
			//log_debug(@"%f %f diff: %f, encoder_delay: %f", _pts, pts, diff, encoder_delay);
			// 如果编码器性能不足, 主动丢包
			if(encoder_delay > 1){
				_pts += duration;
				drop = YES;
			}else if(encoder_delay < -1){
				// 如果超前了, 怎么处理?
			}
		}
	}
	_prev_pts = pts;
	_prev_duration = duration;

	if(drop){
		log_debug(@"drop sample buffer");
		return;
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
		log_debug(@"kCMBlockBuffer error: %@", error);
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
	int sampleRate = _codec.dstFormat.mSampleRate;
	int channels = _codec.dstFormat.mChannelsPerFrame;
	
	int adtsLength = 7;
	char *packet = (char *)malloc(sizeof(char) * adtsLength);
	memset(packet, 0, adtsLength);
	// Variables Recycled by addADTStoPacket
	int profile = 2;  //AAC LC
	//39=MediaCodecInfo.CodecProfileLevel.AACObjectELD;
	int freqIdx = 4;  //44.1KHz
	if(sampleRate == 96000){
		freqIdx = 0;
	}else if(sampleRate == 88200){
		freqIdx = 1;
	}else if(sampleRate == 64000){
		freqIdx = 2;
	}else if(sampleRate == 48000){
		freqIdx = 3;
	}else if(sampleRate == 44100){
		freqIdx = 4;
	}else if(sampleRate == 32000){
		freqIdx = 5;
	}else if(sampleRate == 22050){
		freqIdx = 6;
	}else if(sampleRate == 16000){
		freqIdx = 7;
	}else if(sampleRate == 12000){
		freqIdx = 8;
	}else if(sampleRate == 11025){
		freqIdx = 9;
	}else if(sampleRate == 8000){
		freqIdx = 10;
	}else if(sampleRate == 7350){
		freqIdx = 11;
	}
	int chanCfg = channels;  //MPEG-4 Audio Channel Configuration.
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

@end
