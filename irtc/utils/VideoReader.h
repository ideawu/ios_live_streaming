//
//  VideoReader.h
//  irtc
//
//  Created by ideawu on 16-3-13.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@interface VideoReader : NSObject

- (id)initWithFile:(NSString *)file;

- (CMSampleBufferRef)nextSampleBuffer;

@end
