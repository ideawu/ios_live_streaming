//
//  VideoRecorder.h
//  irtc
//
//  Created by ideawu on 3/4/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

/*
 // H.264
 帧分隔符: 00 00 00 01
 PTS: Present Time Stamp
 SPS: Sequence Parameter Set
 PPS: Picture Parameter Set
 NAL: Network Abstract Layer
 POC: ?
 IDR: Instantaneous Decoder Refresh
	IDR = SPS + PPS + I frame + frames
 SEI: Supplemental Enhancement Information

 NAL Unit 格式: 帧分隔符(3) + type(1) + ...
	type:
		0x67 - SPS
		0x68 - PPS
		0x65 - I Frame
// 文件格式:
 */


@interface VideoRecorder : NSObject

@property (nonatomic, readonly) AVCaptureSession *session;

- (void)start;

@end
