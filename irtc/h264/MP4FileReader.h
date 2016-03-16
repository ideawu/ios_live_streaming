//
//  MP4FileReader.h
//  irtc
//
//  Created by ideawu on 16-3-17.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MP4FileReader : NSObject

+ (MP4FileReader *)readerWithFile:(NSString *)file;

@end
