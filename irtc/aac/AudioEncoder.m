//  http://stackoverflow.com/questions/10817036/can-i-use-avcapturesession-to-encode-an-aac-stream-to-memory

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "AudioEncoder.h"
#import "AACCodec.h"

@interface AudioEncoder(){
	void (^_callback)(NSData *aac, double duration);
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
