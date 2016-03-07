//
//  LiveStream.h
//  irtc
//
//  Created by ideawu on 16-3-7.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LiveStream : NSObject

- (void)sub:(NSString *)url callback:(void (^)(NSData *data))callback;

@end
