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
	AudioReader *ret = [[AudioReader alloc] init];
	ret.url = [NSURL fileURLWithPath:file];
	[ret open];
	return ret;
}

- (void)open{
	NSError *error;
	NSLog(@"open %@", _url);
	_asset = [AVURLAsset URLAssetWithURL:_url options:nil];
	_assetReader = [[AVAssetReader alloc] initWithAsset:_asset error:&error];
	if(error){
		NSLog(@"error: %@", error);
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

@end
