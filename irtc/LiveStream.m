//
//  LiveStream.m
//  irtc
//
//  Created by ideawu on 16-3-7.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import "LiveStream.h"
#include "curl/curl.h"

static size_t icomet_callback(char *ptr, size_t size, size_t nmemb, void *userdata);

@interface LiveStream(){
	CURL *_curl;
	void (^_subCallback)(NSData *data);
}
@property NSString *url;
@end


@implementation LiveStream

- (void)sub:(NSString *)url callback:(void (^)(NSData *data))callback{
	_url = url;
	_subCallback = callback;

	[self performSelectorInBackground:@selector(doSub) withObject:nil];
}

- (void)doSub{
	NSLog(@"connect to %@", _url);
	_curl = curl_easy_init();
	curl_easy_setopt(_curl, CURLOPT_URL, _url.UTF8String);
	curl_easy_setopt(_curl, CURLOPT_NOSIGNAL, 1L);
	curl_easy_setopt(_curl, CURLOPT_USERAGENT, curl_version());
	curl_easy_setopt(_curl, CURLOPT_WRITEFUNCTION, icomet_callback);
	curl_easy_setopt(_curl, CURLOPT_WRITEDATA, self);
	curl_easy_perform(_curl);
	curl_easy_cleanup(_curl);

	NSLog(@"connection lost, will try to reconnect");
	[NSThread sleepForTimeInterval:2];
	[self performSelectorInBackground:@selector(doSub) withObject:nil];
}

static NSData *base64_decode(NSString *str){
	NSData *data = [[NSData alloc] initWithBase64EncodedString:str options:NSDataBase64DecodingIgnoreUnknownCharacters];
	return data;
}

// run in different thread(the curl thread)
- (void)streamCallback:(NSData *)data{
	NSError *err = nil;
	id obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&err];
	if(err){
		return;
	}
	if(!obj || ![obj isKindOfClass:[NSDictionary class]]){
		return;
	}
	NSDictionary *dict = (NSDictionary *)obj;
	NSString *type = [dict objectForKey:@"type"];
	NSString *content = [dict objectForKey:@"content"];
	if(!type){
		return;
	}
	if([type isEqualToString:@"data"]){
		if(content){
			NSData *content_data = base64_decode(content);
			if(content_data){
				if(_subCallback){
					_subCallback(content_data);
				}
			}else{
				NSLog(@"bad content");
			}
		}
	}
}

@end

// this function is called in a separated thread
static size_t icomet_callback(char *ptr, size_t size, size_t nmemb, void *userdata){
	static NSMutableData *buf = nil;
	if(buf == nil){
		buf = [[NSMutableData alloc] init];
	}
	const size_t sizeInBytes = size*nmemb;
	[buf appendBytes:ptr length:sizeInBytes];

	const char *start = (const char *)buf.bytes;
	const char *end = start + buf.length;
	const char *sp, *ep;
	sp = ep = start;
	while(ep < end){
		char c = *ep;
		ep ++;
		if(c == '\n'){
			NSUInteger len = ep - sp;
			NSData *data = [[NSData alloc] initWithBytesNoCopy:(void *)sp length:len freeWhenDone:NO];
			sp = ep;

			LiveStream *controller = (__bridge LiveStream *)userdata;
			[controller streamCallback:data];
		}
	}
	if(sp != start){
		NSRange range = NSMakeRange(0, sp - start);
		[buf replaceBytesInRange:range withBytes:NULL length:0];
	}

	return sizeInBytes;
}
