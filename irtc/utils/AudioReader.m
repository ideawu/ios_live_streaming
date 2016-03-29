//
//  AudioReader.m
//  irtc
//
//  Created by ideawu on 3/10/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "AudioReader.h"

@interface AudioReader(){
	AVURLAsset *_asset;
	AVAssetReader *_assetReader;
	AVAssetReaderTrackOutput *_audioOutput;
	AVAssetTrack* _audio_track;
}
@property NSURL *url;
@end

@implementation AudioReader

+ (AudioReader *)readerWithFile:(NSString *)file{
	AudioReader *ret = [[AudioReader alloc] initWithFile:file];
	return ret;
}

- (id)initWithFile:(NSString *)file{
	self = [super init];
	_url = [NSURL fileURLWithPath:file];
	[self open];
	return self;
}

- (void)open{
	NSError *error;
	log_debug(@"open %@", _url);
	_asset = [AVURLAsset URLAssetWithURL:_url options:nil];
	_assetReader = [[AVAssetReader alloc] initWithAsset:_asset error:&error];
	if(error){
		log_debug(@"error: %@", error);
		return;
	}
	
	NSDictionary *settings;
	_audio_track = [_asset tracksWithMediaType:AVMediaTypeAudio].lastObject;
	if(_audio_track){
		settings = @{
					 AVFormatIDKey: @(kAudioFormatLinearPCM),
					 };
		_audioOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:_audio_track
														outputSettings:settings];
		if([_assetReader canAddOutput:_audioOutput]){
			[_assetReader addOutput:_audioOutput];
		}
	}
	[_assetReader startReading];
}

- (CMSampleBufferRef)nextSampleBuffer{
	CMSampleBufferRef sampleBuffer = [_audioOutput copyNextSampleBuffer];
	return sampleBuffer;
}

- (NSData *)nextSampleData{
	CMSampleBufferRef sampleBuffer = [_audioOutput copyNextSampleBuffer];
	if(!sampleBuffer){
		return nil;
	}
	
	NSMutableData *data = [[NSMutableData alloc] init];
	OSStatus err;
	AudioBufferList audioBufferList;
	CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
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
		log_debug(@"%d error", __LINE__);
	}
	for (NSUInteger i = 0; i < audioBufferList.mNumberBuffers; i++) {
		AudioBuffer audioBuffer = audioBufferList.mBuffers[i];
		[data appendBytes:audioBuffer.mData length:audioBuffer.mDataByteSize];
	}
	
	_format = *CMAudioFormatDescriptionGetStreamBasicDescription((CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer));
	
	CFRelease(blockBuffer);
	CFRelease(sampleBuffer);
	return data;
}

@end
