//
//  MP4FileReader.h
//  irtc
//
//  Created by ideawu on 16-3-17.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FileReader.h"

@interface MP4FileReader : NSObject

@property (readonly) FileReader *file;

+ (MP4FileReader *)readerAtPath:(NSString *)path;

- (void)refresh;
- (void)reloadMDATLength;
- (NSData *)nextNALU;

@end
