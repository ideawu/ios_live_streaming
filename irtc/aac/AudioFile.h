//
//  AudioFile.h
//  irtc
//
//  Created by ideawu on 16-3-10.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

/*
 由于 AudioConverterFillComplexBuffer 在 Mac 上似乎和 AVCaptureSession 冲突,
 所以只能先将 PCM 写入文件, 然后用文件转码.
 */

#import <Foundation/Foundation.h>

@interface AudioFile : NSObject

@end
