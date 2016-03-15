//
//  MovieCaptureFile.h
//  irtc
//
//  Created by ideawu on 3/15/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MovieCaptureFile : NSObject

@property (nonatomic) NSString *filename;
@property (nonatomic) int width;
@property (nonatomic) int height;
@property (nonatomic) int videoBitrate;
@property (nonatomic) int audioSampleRate;

- (void)start;
- (void)stop;

@end
