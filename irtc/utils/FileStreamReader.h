//
//  FileReader.h
//  irtc
//
//  Created by ideawu on 3/16/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface FileStreamReader : NSObject

@property (readonly) int64_t total;
@property (readonly) int64_t offset;
@property (readonly) int64_t available;

+ (FileStreamReader *)readerForFile:(NSString *)file;

- (void)refresh;
- (void)skip:(long)size;
- (void)read:(void *)buf size:(long)size;

@end
