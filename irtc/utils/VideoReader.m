//
//  VideoReader.m
//  irtc
//
//  Created by ideawu on 16-3-13.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import "VideoReader.h"

@interface VideoReader(){
	AVURLAsset *_asset;
	AVAssetReader *_assetReader;
	AVAssetReaderTrackOutput *_videoOutput;
	AVAssetTrack* _video_track;
}
@property NSURL *url;
@end

@implementation VideoReader

- (id)initWithFile:(NSString *)file{
	self = [super init];
	_url = [NSURL fileURLWithPath:file];
	[self open];
	return self;
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
	_video_track = [_asset tracksWithMediaType:AVMediaTypeVideo].lastObject;
	if(_video_track){
		settings = @{
					 (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
					 };
		_videoOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:_video_track
														outputSettings:settings];
		if([_assetReader canAddOutput:_videoOutput]){
			[_assetReader addOutput:_videoOutput];
		}
	}
	[_assetReader startReading];
}

- (CMSampleBufferRef)nextSampleBuffer{
	CMSampleBufferRef sampleBuffer = [_videoOutput copyNextSampleBuffer];
	return sampleBuffer;
}

//- (CVPixelBufferRef)nextPixelBuffer{
//	CMSampleBufferRef buffer = [_videoOutput copyNextSampleBuffer];
//	if(!buffer){
//		//NSLog(@"nil buffer");
//		return nil;
//	}
//	// CVImageBufferRef 即是 CVPixelBufferRef
//	CVPixelBufferRef imageBuffer = CMSampleBufferGetImageBuffer(buffer);
//	CVPixelBufferLockBaseAddress(imageBuffer, 0);
//	uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
//	size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
//	size_t width = CVPixelBufferGetWidth(imageBuffer);
//	size_t height = CVPixelBufferGetHeight(imageBuffer);
//
//	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
//	CGContextRef context = CGBitmapContextCreate(baseAddress,
//												 width, height,
//												 8, bytesPerRow,
//												 colorSpace,
//												 kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
//	CGColorSpaceRelease(colorSpace);
//	CGContextRelease(context);
//	return imageBuffer;
//}

@end
