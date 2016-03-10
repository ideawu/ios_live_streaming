//
//  AudioDecoder.h
//  irtc
//
//  Created by ideawu on 3/10/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface AudioDecoder : NSObject

@property AudioStreamBasicDescription format;

- (void)appendData:(NSData *)data pts:(double)pts;

@end
