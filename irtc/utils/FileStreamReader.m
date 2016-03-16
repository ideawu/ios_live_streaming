//
//  FileReader.m
//  irtc
//
//  Created by ideawu on 3/16/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "FileStreamReader.h"
#import <sys/stat.h>

@interface FileStreamReader(){
}
@property (nonatomic) NSString *file;
@property (nonatomic) FILE *fp;
@end

@implementation FileStreamReader

+ (FileStreamReader *)readerForFile:(NSString *)file{
	FILE *fp = fopen(file.UTF8String, "rb");
	if(!fp){
		return nil;
	}
	FileStreamReader *ret = [[FileStreamReader alloc] init];
	ret.fp = fp;
	ret.file = file;
	[ret refresh];
	return ret;
}

- (id)init{
	self = [super init];
	_total = 0;
	_offset = 0;
	_available = 0;
	return self;
}

- (void)refresh{
	struct stat st;
	fstat(fileno(_fp), &st);
	_total = st.st_size;
	_available = _total - _offset;
}

- (void)seekTo:(long)pos{
	long step = pos - _offset;
	[self skip:step];
}

- (void)skip:(long)size{
	_offset += size;
	_available -= size;
	fseek(_fp, size, SEEK_CUR);
}

- (void)read:(void *)buf size:(long)size{
	_offset += size;
	_available -= size;
	fread(buf, 1, size, _fp);
}

@end
