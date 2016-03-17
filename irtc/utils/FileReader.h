//
//  FileReader.h
//  irtc
//
//  Created by ideawu on 3/16/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface FileReader : NSObject

@property (readonly) int64_t total;
@property (readonly) int64_t offset;
@property (readonly) int64_t available;

@property (readonly) NSString *path;

+ (FileReader *)readerAtPath:(NSString *)path;

- (void)refresh;
- (void)seekTo:(long)offset;
- (void)skip:(long)size;
- (int)read:(void *)buf size:(long)size;

@end
