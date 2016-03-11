//
//  AudioDecoder.h
//  irtc
//
//  Created by ideawu on 3/10/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@interface AudioDecoder : NSObject

//- (void)setADTS:(NSData *)adts;

- (void)start:(void (^)(NSData *pcm, double duration))callback;
- (void)shutdown;

- (void)decode:(NSData *)aac;

@end
