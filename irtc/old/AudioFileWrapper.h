//
//  AudioFileWrapper.h
//  irtc
//
//  Created by ideawu on 3/11/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@interface AudioFileWrapper : NSObject

- (void)start;
- (void)decode:(NSData *)audioData;

@end
