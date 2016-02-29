#import "Test.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>

@interface Test ()<AVCaptureAudioDataOutputSampleBufferDelegate,AVCaptureVideoDataOutputSampleBufferDelegate>
{
	AVAssetWriter *assetWriter;
	AVAssetWriterInput *audioWriterInput;
	AVAssetWriterInput *videoWriterInput;
	AVCaptureConnection *_audioConnection;
	AVCaptureConnection *_videoConnection;
	
	UIView *preview;
	BOOL _isRecording;
	
	BOOL readyForAudio;
	BOOL readyForVideo;
	BOOL videoWritten;
	CMTime _timeOffset;
	CMTime _audioTimestamp;
	CMTime _videoTimestamp;
	
	IBOutlet UIButton *_recordBtn;
	IBOutlet UIButton *_playBtn;
	
	dispatch_queue_t _captureVideoDispatchQueue;
	
	AVCaptureDevice *_captureDeviceFront;
	AVCaptureDevice *_captureDeviceBack;
	
	AVCaptureDeviceInput *_captureDeviceInputFront;
	AVCaptureDeviceInput *_captureDeviceInputBack;
	
}

@property(nonatomic,retain) NSURL *outputPath;
@property(nonatomic,retain) AVCaptureSession * captureSession;
@property(nonatomic,retain) AVCaptureAudioDataOutput * output;

@end

@implementation ViewController

@synthesize captureSession = _captureSession;
@synthesize output = _output;
@synthesize outputPath = _outputPath;

- (BOOL)prefersStatusBarHidden{
	return YES;
}

- (void)viewDidLoad {
	
	_captureVideoDispatchQueue = dispatch_queue_create("RD-SCREEN-RECORD", DISPATCH_QUEUE_SERIAL);
	
	_isRecording=NO;
	readyForAudio=NO;
	readyForVideo=NO;
	videoWritten=NO;
	
	NSArray *searchPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	
	//    NSString *outPath = [NSString stringWithFormat:@"%@%@", NSTemporaryDirectory(), @"video.mp4"];
	NSString *outPath=[[searchPaths objectAtIndex:0] stringByAppendingPathComponent:@"video.mp4"];
	unlink([outPath UTF8String]);
	self.outputPath = [NSURL fileURLWithPath:outPath];
	
	[self setupAssetWriter];
	[self setupCaptureSession];
	[self setupPreview];
	
	[super viewDidLoad];
}

#pragma mark - Camera Preview

- (void)setupPreview{
	
	preview = [[UIView alloc]init];
	preview.frame = CGRectMake(0, 0, 320, 320);
	[self.view addSubview:preview];
	
	AVCaptureVideoPreviewLayer* previewLayer = [AVCaptureVideoPreviewLayer layerWithSession: _captureSession];
	previewLayer.frame = preview.bounds;
	previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
	[preview.layer addSublayer: previewLayer];
}

#pragma mark - AVCaptureSession


- (void)setupCaptureSession{
	_captureSession = [[AVCaptureSession alloc] init];
	
	[_captureSession  beginConfiguration];
	
	_captureSession.sessionPreset=AVCaptureSessionPresetMedium;
	
	_captureDeviceFront = [self captureDeviceForPosition:AVCaptureDevicePositionFront];
	_captureDeviceBack = [self captureDeviceForPosition:AVCaptureDevicePositionBack];
	
	NSError *error = nil;
	_captureDeviceInputFront = [AVCaptureDeviceInput deviceInputWithDevice:_captureDeviceFront error:&error];
	if (error) {
		NSLog(@"error setting up front camera input (%@)", error);
		error = nil;
	}
	
	_captureDeviceInputBack = [AVCaptureDeviceInput deviceInputWithDevice:_captureDeviceBack error:&error];
	if (error) {
		NSLog(@"error setting up back camera input (%@)", error);
		error = nil;
	}
	
	if ([_captureSession canAddInput:_captureDeviceInputFront])
	{
		[_captureSession addInput:_captureDeviceInputFront];
	}
	
	AVCaptureDevice *audioCaptureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
	AVCaptureDeviceInput *audioIn = [[AVCaptureDeviceInput alloc] initWithDevice:audioCaptureDevice error:nil];
	if ([_captureSession canAddInput:audioIn])
	{
		[_captureSession addInput:audioIn];
	}
	
	AVCaptureAudioDataOutput *audioOut = [[AVCaptureAudioDataOutput alloc] init];
	[audioOut setSampleBufferDelegate:self queue:_captureVideoDispatchQueue];
	
	
	
	AVCaptureDevice *videoCaptureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	AVCaptureDeviceInput *videoIn = [[AVCaptureDeviceInput alloc] initWithDevice:videoCaptureDevice error:nil];
	
	if ([_captureSession canAddInput:videoIn])
	{
		[_captureSession addInput:videoIn];
	}
	
	AVCaptureVideoDataOutput *videoOut = [[AVCaptureVideoDataOutput alloc] init];
	[videoOut setAlwaysDiscardsLateVideoFrames:NO];
	[videoOut setVideoSettings:[NSDictionary dictionaryWithObject:
								[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]//kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
														   forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
	[videoOut setSampleBufferDelegate:self queue:_captureVideoDispatchQueue];
	
	if ([_captureSession canAddOutput:audioOut])
	{
		[_captureSession addOutput:audioOut];
	}
	
	_audioConnection = [audioOut connectionWithMediaType:AVMediaTypeAudio];
	
	
	if ([_captureSession canAddOutput:videoOut])
	{
		[_captureSession addOutput:videoOut];
	}
	NSString *sessionPreset = [_captureSession sessionPreset];
	
	// apply presets
	if ([_captureSession canSetSessionPreset:sessionPreset]) {
		[_captureSession setSessionPreset:sessionPreset];
	}
	
	_videoConnection = [videoOut connectionWithMediaType:AVMediaTypeVideo];
	
	if ([_videoConnection isVideoStabilizationSupported])
		[_videoConnection setEnablesVideoStabilizationWhenAvailable:YES];
	
	[_captureSession commitConfiguration];
	[_captureSession startRunning];
}

- (AVCaptureDevice *)captureDeviceForPosition:(AVCaptureDevicePosition)position
{
	NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
	for (AVCaptureDevice *device in devices) {
		if ([device position] == position) {
			return device;
		}
	}
	
	return nil;
}

#pragma mark - AVAssetWriter

- (void)setupAssetWriter{
	assetWriter = [[AVAssetWriter alloc] initWithURL:_outputPath fileType:AVFileTypeQuickTimeMovie error:nil];
	
#if 0
	// only audio test
	AudioChannelLayout acl;
	bzero(&acl, sizeof(acl));
	acl.mChannelLayoutTag = kAudioChannelLayoutTag_Mono; //kAudioChannelLayoutTag_Stereo;
	NSDictionary *audioOutputSettings = [NSDictionary dictionaryWithObjectsAndKeys:
										 [NSNumber numberWithInt: kAudioFormatULaw],AVFormatIDKey,
										 [NSNumber numberWithFloat:44100.0],AVSampleRateKey,
										 [NSData dataWithBytes: &acl length: sizeof( AudioChannelLayout ) ], AVChannelLayoutKey,
										 [NSNumber numberWithInt:1],AVNumberOfChannelsKey,
										 [NSNumber numberWithInt:64000],AVEncoderBitRateKey,
										 nil];
	audioWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:audioOutputSettings];
	[audioWriterInput setExpectsMediaDataInRealTime:YES];
	assetWriter = [AVAssetWriter assetWriterWithURL:_outputPath fileType:AVFileTypeWAVE error:nil];
	[assetWriter addInput:audioWriterInput];
	readyForAudio=YES;
	readyForVideo=YES;
#else
	//  video Configuration
	NSDictionary *videoCleanApertureSettings = [NSDictionary dictionaryWithObjectsAndKeys:
												[NSNumber numberWithInt:480], AVVideoCleanApertureWidthKey,
												[NSNumber numberWithInt:480], AVVideoCleanApertureHeightKey,
												[NSNumber numberWithInt:2], AVVideoCleanApertureHorizontalOffsetKey,
												[NSNumber numberWithInt:2], AVVideoCleanApertureVerticalOffsetKey,
												nil];
	
	
	NSDictionary *videoAspectRatioSettings = [NSDictionary dictionaryWithObjectsAndKeys:
											  [NSNumber numberWithInt:1], AVVideoPixelAspectRatioHorizontalSpacingKey,
											  [NSNumber numberWithInt:1],AVVideoPixelAspectRatioVerticalSpacingKey,
											  nil];
	
	NSDictionary *codecSettings = [NSDictionary dictionaryWithObjectsAndKeys:
								   [NSNumber numberWithInt:1024*1000], AVVideoAverageBitRateKey,
								   [NSNumber numberWithInt:30],AVVideoMaxKeyFrameIntervalKey,
								   videoCleanApertureSettings, AVVideoCleanApertureKey,
								   videoAspectRatioSettings, AVVideoPixelAspectRatioKey,
								   AVVideoProfileLevelH264Main30, AVVideoProfileLevelKey,
								   nil];
	
	NSDictionary *videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
								   AVVideoCodecH264, AVVideoCodecKey,
								   codecSettings,AVVideoCompressionPropertiesKey,
								   [NSNumber numberWithInt:480], AVVideoWidthKey,
								   [NSNumber numberWithInt:480], AVVideoHeightKey,
								   nil];
	
	videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
	NSParameterAssert(videoWriterInput);
	videoWriterInput.expectsMediaDataInRealTime = YES;
	
	// audio Configuration
	AudioChannelLayout acl;
	bzero( &acl, sizeof(acl));
	acl.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;//kAudioChannelLayoutTag_Mono
	
	NSDictionary* audioOutputSettings = nil;
	
	audioOutputSettings = [NSDictionary dictionaryWithObjectsAndKeys:
						   [ NSNumber numberWithInt: kAudioFormatMPEG4AAC ], AVFormatIDKey,
						   [ NSNumber numberWithInt: 2 ], AVNumberOfChannelsKey,
						   [ NSNumber numberWithFloat: 44100.0 ], AVSampleRateKey,
						   [ NSNumber numberWithInt: 64000 ], AVEncoderBitRateKey,
						   [ NSData dataWithBytes: &acl length: sizeof( acl ) ], AVChannelLayoutKey,
						   nil];
	audioWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType: AVMediaTypeAudio outputSettings: audioOutputSettings];
	audioWriterInput.expectsMediaDataInRealTime = YES;
#endif
	
	//    if ( [assetWriter canAddInput:videoWriterInput] )
	//    {
	//        [assetWriter addInput:videoWriterInput];
	//    }
	//
	//    audioWriterInput.expectsMediaDataInRealTime = YES;
	//
	//    if ( [assetWriter canAddInput:audioWriterInput] )
	//    {
	//        [assetWriter addInput:audioWriterInput];
	//    }
	//    readyForAudio=YES;
	//    readyForVideo=YES;
	
}

#pragma mark - AssetWriterAudioInput, AssetWriterVideoInput

- (BOOL)_setupAssetWriterAudioInput:(CMFormatDescriptionRef)currentFormatDescription
{
	const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(currentFormatDescription);
	if (!asbd) {
		NSLog(@"audio stream description used with non-audio format description");
		return NO;
	}
	
	unsigned int channels = asbd->mChannelsPerFrame;
	double sampleRate = asbd->mSampleRate;
	int bitRate = 64000;
	
	NSLog(@"audio stream setup, channels (%d) sampleRate (%f)", channels, sampleRate);
	
	size_t aclSize = 0;
	const AudioChannelLayout *currentChannelLayout = CMAudioFormatDescriptionGetChannelLayout(currentFormatDescription, &aclSize);
	NSData *currentChannelLayoutData = ( currentChannelLayout && aclSize > 0 ) ? [NSData dataWithBytes:currentChannelLayout length:aclSize] : [NSData data];
	
	NSDictionary *audioCompressionSettings = [NSDictionary dictionaryWithObjectsAndKeys:
											  [NSNumber numberWithInt:kAudioFormatMPEG4AAC], AVFormatIDKey,
											  [NSNumber numberWithUnsignedInt:channels], AVNumberOfChannelsKey,
											  [NSNumber numberWithDouble:sampleRate], AVSampleRateKey,
											  [NSNumber numberWithInt:bitRate], AVEncoderBitRateKey,
											  currentChannelLayoutData, AVChannelLayoutKey, nil];
	
	if ([assetWriter canApplyOutputSettings:audioCompressionSettings forMediaType:AVMediaTypeAudio]) {
		audioWriterInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio outputSettings:audioCompressionSettings];
		audioWriterInput.expectsMediaDataInRealTime = YES;
		NSLog(@"prepared audio-in with compression settings sampleRate (%f) channels (%d) bitRate (%d)", sampleRate, channels, bitRate);
		if ([assetWriter canAddInput:audioWriterInput]) {
			[assetWriter addInput:audioWriterInput];
		} else {
			NSLog(@"couldn't add asset writer audio input");
			return NO;
		}
	} else {
		NSLog(@"couldn't apply audio output settings");
		return NO;
	}
	
	return YES;
	
}

- (BOOL)_setupAssetWriterVideoInput:(CMFormatDescriptionRef)currentFormatDescription
{
	CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(currentFormatDescription);
	
	float bitRate = 87500.0f * 8.0f;
	NSInteger frameInterval = 30;
	
	NSDictionary *compressionSettings = [NSDictionary dictionaryWithObjectsAndKeys:
										 [NSNumber numberWithFloat:bitRate], AVVideoAverageBitRateKey,
										 [NSNumber numberWithInteger:frameInterval], AVVideoMaxKeyFrameIntervalKey,
										 nil];
	
	NSDictionary *videoCompressionSettings = [NSDictionary dictionaryWithObjectsAndKeys:
											  AVVideoCodecH264, AVVideoCodecKey,
											  AVVideoScalingModeResizeAspectFill, AVVideoScalingModeKey,
											  [NSNumber numberWithInteger:dimensions.width], AVVideoWidthKey,
											  [NSNumber numberWithInteger:dimensions.width], AVVideoHeightKey, // square format
											  compressionSettings, AVVideoCompressionPropertiesKey,
											  nil];
	
	if ([assetWriter canApplyOutputSettings:videoCompressionSettings forMediaType:AVMediaTypeVideo]) {
		
		videoWriterInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:videoCompressionSettings];
		videoWriterInput.expectsMediaDataInRealTime = YES;
		videoWriterInput.transform = CGAffineTransformIdentity;
		NSLog(@"prepared video-in with compression settings bps (%f) frameInterval (%d)", bitRate, frameInterval);
		if ([assetWriter canAddInput:videoWriterInput]) {
			[assetWriter addInput:videoWriterInput];
		} else {
			NSLog(@"couldn't add asset writer video input");
			return NO;
		}
		
	} else {
		
		NSLog(@"couldn't apply video output settings");
		return NO;
		
	}
	
	return YES;
}

#pragma mark - Record, Stop


- (IBAction)onRecord:(id)sender {
	if (_isRecording) {
		NSLog(@"stop recording");
		
		[self stopRecording];
		
	}else{
		NSLog(@"start recording");
		_timeOffset = kCMTimeZero;
		_audioTimestamp = kCMTimeZero;
		_videoTimestamp = kCMTimeZero;
		_isRecording=YES;
	}
}


-(IBAction)onStop
{
	[self stopRecording];
	
	//    NSError *error;
	//    AVAudioPlayer * audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:self.outputPath error:&error];
	//    audioPlayer.numberOfLoops = -1;
	//
	//    if (audioPlayer == nil){
	//        NSLog(@"error: %@",[error description]);
	//    }else{
	//        NSLog(@"playing");
	//        [audioPlayer play];
	//    }
}

-(void)stopRecording
{
	_isRecording=NO;
	readyForAudio=NO;
	readyForVideo=NO;
	videoWritten=NO;
	[videoWriterInput markAsFinished];
	[audioWriterInput markAsFinished];
	[assetWriter  finishWritingWithCompletionHandler:^{
		NSLog(@"assetWriterStatus:%u",assetWriter.status);
	}];
	
	NSDictionary *outputFileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[NSString stringWithFormat:@"%@",self.outputPath] error:nil];
	NSLog (@"file size: %llu", [outputFileAttributes fileSize]);
}

#pragma mark - AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate

-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
	CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
	CFRetain(sampleBuffer);
	CFRetain(formatDescription);
	dispatch_async(_captureVideoDispatchQueue, ^{
		
		if (!CMSampleBufferDataIsReady(sampleBuffer)) {
			NSLog(@"sample buffer data is not ready");
			CFRelease(sampleBuffer);
			CFRelease(formatDescription);
			return;
		}
		
		if (!_isRecording) {
			CFRelease(sampleBuffer);
			CFRelease(formatDescription);
			return;
		}
		
		if (!assetWriter) {
			CFRelease(sampleBuffer);
			CFRelease(formatDescription);
			return;
		}
		
		BOOL isAudio = (connection == _audioConnection?YES:NO);
		BOOL isVideo = (connection == _videoConnection?YES:NO);
		BOOL wasReadyToRecord = (readyForAudio &&readyForVideo);
		
		if (isAudio && !readyForAudio) {
			readyForAudio = (unsigned int)[self _setupAssetWriterAudioInput:formatDescription];
			NSLog(@"ready for audio (%d)",readyForAudio);
		}
		
		if (isVideo && !readyForVideo) {
			readyForVideo = (unsigned int)[self _setupAssetWriterVideoInput:formatDescription];
			NSLog(@"ready for video (%d)",readyForVideo);
		}
		
		BOOL isReadyToRecord = (readyForAudio && readyForVideo);
		
		// calculate the length of the interruption
		if (isAudio) {
			CMTime time = isVideo ? _videoTimestamp : _audioTimestamp;
			// calculate the appropriate time offset
			if (CMTIME_IS_VALID(time)) {
				CMTime pTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
				if (CMTIME_IS_VALID(_timeOffset)) {
					pTimestamp = CMTimeSubtract(pTimestamp, _timeOffset);
				}
				
				CMTime offset = CMTimeSubtract(pTimestamp, _audioTimestamp);
				_timeOffset = (_timeOffset.value == 0) ? offset : CMTimeAdd(_timeOffset, offset);
				NSLog(@"new calculated offset %f valid (%d)", CMTimeGetSeconds(_timeOffset), CMTIME_IS_VALID(_timeOffset));
			} else {
				NSLog(@"invalid audio timestamp, no offset update");
			}
			
			_audioTimestamp.flags = 0;
			_videoTimestamp.flags = 0;
			
		}
		
		if (isVideo && isReadyToRecord) {
			
			CMSampleBufferRef bufferToWrite = NULL;
			
			if (_timeOffset.value > 0) {
				bufferToWrite = [self _createOffsetSampleBuffer:sampleBuffer withTimeOffset:_timeOffset];
				if (!bufferToWrite) {
					NSLog(@"error subtracting the timeoffset from the sampleBuffer");
				}
			} else {
				bufferToWrite = sampleBuffer;
				CFRetain(bufferToWrite);
			}
			
			if (bufferToWrite) {
				// update the last video timestamp
				CMTime time = CMSampleBufferGetPresentationTimeStamp(bufferToWrite);
				CMTime duration = CMSampleBufferGetDuration(bufferToWrite);
				if (duration.value > 0)
					time = CMTimeAdd(time, duration);
				
				if (time.value > _videoTimestamp.value) {
					//                    [self _writeSampleBuffer:bufferToWrite ofType:AVMediaTypeVideo];
					_videoTimestamp = time;
					videoWritten = YES;
				}
				CFRelease(bufferToWrite);
			}
			
		} else if (isAudio && isReadyToRecord) {
			
			CMSampleBufferRef bufferToWrite = NULL;
			
			if (_timeOffset.value > 0) {
				bufferToWrite = [self _createOffsetSampleBuffer:sampleBuffer withTimeOffset:_timeOffset];
				if (!bufferToWrite) {
					NSLog(@"error subtracting the timeoffset from the sampleBuffer");
				}
			} else {
				bufferToWrite = sampleBuffer;
				CFRetain(bufferToWrite);
			}
			
			if (bufferToWrite && videoWritten) {
				// update the last audio timestamp
				CMTime time = CMSampleBufferGetPresentationTimeStamp(bufferToWrite);
				CMTime duration = CMSampleBufferGetDuration(bufferToWrite);
				if (duration.value > 0)
					time = CMTimeAdd(time, duration);
				
				if (time.value > _audioTimestamp.value) {
					[self _writeSampleBuffer:bufferToWrite ofType:AVMediaTypeAudio];
					_audioTimestamp = time;
				}
				CFRelease(bufferToWrite);
			}
		}
		
		if ( !wasReadyToRecord && isReadyToRecord ) {
		}
		
		CFRelease(sampleBuffer);
		CFRelease(formatDescription);
		//    }];
	});
}

- (CMSampleBufferRef)_createOffsetSampleBuffer:(CMSampleBufferRef)sampleBuffer withTimeOffset:(CMTime)timeOffset
{
	CMItemCount itemCount;
	
	OSStatus status = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, 0, NULL, &itemCount);
	if (status) {
		NSLog(@"couldn't determine the timing info count");
		return NULL;
	}
	
	CMSampleTimingInfo *timingInfo = (CMSampleTimingInfo *)malloc(sizeof(CMSampleTimingInfo) * (unsigned long)itemCount);
	if (!timingInfo) {
		NSLog(@"couldn't allocate timing info");
		return NULL;
	}
	
	status = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, itemCount, timingInfo, &itemCount);
	if (status) {
		free(timingInfo);
		timingInfo = NULL;
		NSLog(@"failure getting sample timing info array");
		return NULL;
	}
	
	for (CMItemCount i = 0; i < itemCount; i++) {
		timingInfo[i].presentationTimeStamp = CMTimeSubtract(timingInfo[i].presentationTimeStamp, timeOffset);
		timingInfo[i].decodeTimeStamp = CMTimeSubtract(timingInfo[i].decodeTimeStamp, timeOffset);
	}
	
	CMSampleBufferRef outputSampleBuffer;
	CMSampleBufferCreateCopyWithNewTiming(kCFAllocatorDefault, sampleBuffer, itemCount, timingInfo, &outputSampleBuffer);
	
	if (timingInfo) {
		free(timingInfo);
		timingInfo = NULL;
	}
	
	return outputSampleBuffer;
}

- (void)_writeSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(NSString *)mediaType
{
	if ( assetWriter.status == AVAssetWriterStatusUnknown ) {
		
		if ([assetWriter startWriting]) {
			CMTime startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
			[assetWriter startSessionAtSourceTime:startTime];
			NSLog(@"asset writer started writing with status (%d)", assetWriter.status);
		} else {
			NSLog(@"asset writer error when starting to write (%@)", [assetWriter error]);
		}
		
	}
	
	if ( assetWriter.status == AVAssetWriterStatusFailed ) {
		NSLog(@"asset writer failure, (%@)", assetWriter.error.localizedDescription);
		return;
	}
	
	if ( assetWriter.status == AVAssetWriterStatusWriting ) {
		
		if (mediaType == AVMediaTypeVideo) {
			if (videoWriterInput.readyForMoreMediaData) {
				if (![videoWriterInput appendSampleBuffer:sampleBuffer]) {
					NSLog(@"asset writer error appending video (%@)", [assetWriter error]);
				}
			}
		} else if (mediaType == AVMediaTypeAudio) {
			if (audioWriterInput.readyForMoreMediaData) {
				if (![audioWriterInput appendSampleBuffer:sampleBuffer]) {
					NSLog(@"asset writer error appending audio (%@)", [assetWriter error]);
				}
			}
		}
		
	}
	
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	// Dispose of any resources that can be recreated.
}

-(void) saveVideoToCameraRoll{
	
	ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
	[library writeVideoAtPathToSavedPhotosAlbum:self.outputPath completionBlock:^(NSURL *assetURL, NSError *error){
		NSLog(@"ASSET URL: %@", [assetURL path]);
		
		if(error) {
			NSLog(@"CameraViewController: Error on saving movie : %@ {imagePickerController}", error);
		}
		else {
			NSLog(@"Video salvato correttamente in URL: %@", assetURL);
			BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:[self.outputPath path]];
			NSLog(@"IL FILE ESISTE: %hhd", fileExists);
			NSLog(@"E PESA: %@", [[[NSFileManager defaultManager] attributesOfItemAtPath:  [self.outputPath path] error:&error] objectForKey:NSFileSize]);
		}
	}];
}

@end