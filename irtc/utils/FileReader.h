//
//  FileReader.h
//  irtc
//
//  Created by ideawu on 3/16/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface FileReader : NSObject

/**
 total bytes of this file
 */
@property (readonly) long total;
@property (readonly) long offset;
@property (readonly) long available;

@property (readonly) NSString *path;

+ (FileReader *)readerAtPath:(NSString *)path;

- (void)refresh;
- (void)seekTo:(long)offset;
- (void)skip:(long)size;
- (int)read:(void *)buf size:(long)size;

@end
