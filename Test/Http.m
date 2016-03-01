/*
 Copyright (c) 2014 ideawu. All rights reserved.
 Use of this source code is governed by a license that can be
 found in the LICENSE file.
 
 @author:  ideawu
 @website: http://www.cocoaui.com/
 */

#include "TargetConditionals.h"
#ifndef TARGET_OS_MAC
#import <UIKit/UIKit.h>
#endif
#import "Http.h"

#define HTTP_GET  0
#define HTTP_POST 1


static NSString *urlencode(NSString *str){
	CFStringEncoding cfEncoding = kCFStringEncodingUTF8;
	str = (__bridge NSString *)CFURLCreateStringByAddingPercentEscapes(
																	   NULL,
																	   (CFStringRef)str,
																	   NULL,
																	   CFSTR("!*'();:@&=+$,/?%#[]"),
																	   cfEncoding
																	   );
	return str;
}

static int is_safe_char(char c){
	if(c == '.' || c == '-' || c == '_'){
		return 1;
	}else if(c >= '0' && c <= '9'){
		return 1;
	}else if(c >= 'A' && c <= 'Z'){
		return 1;
	}else if(c >= 'a' && c <= 'z'){
		return 1;
	}
	return 0;
}

static NSString *urlencode_data(NSData *data){
	NSMutableString *ret = [[NSMutableString alloc] init];
	char *ptr = (char *)data.bytes;
	int len = (int)data.length;
	for(int i=0; i<len; i++){
		char c = ptr[i];
		if(is_safe_char(c)){
			[ret appendFormat:@"%c", c];
		}else{
			[ret appendFormat:@"%%%02X", c];
		}
	}
	return ret;
}


// TODO:
static NSArray *cookies = nil;
static NSArray *resp_cookies = nil;

void http_request_raw(NSString *urlStr, id params, int method, void (^callback)(NSData *)){
	NSMutableString *query = [[NSMutableString alloc] init];
	if([params isKindOfClass: [NSString class]]){
		query = params;
	}else if([params isKindOfClass: [NSDictionary class]]){
		NSUInteger n = [(NSDictionary *)params count];
		for (NSString *key in params) {
			id v = [params objectForKey:key];
			[query appendString:urlencode(key)];
			[query appendString:@"="];
			NSString *val;
			if([v class] == [NSData class]){
				val = urlencode_data((NSData *)v);
			}else{
				val = urlencode([NSString stringWithFormat:@"%@", v]);
			}
			[query appendString:val];
			if(--n > 0){
				[query appendString:@"&"];
			}
		}
	}
	
	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
	[request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
	[request setTimeoutInterval:10];
	
	//[request addValue:@"https://www.cocoaui.com/?ios" forHTTPHeaderField:@"Referer"];
	
	NSString *ua = @"IObj-iphone";
#ifndef TARGET_OS_MAC
	UIDevice *_dev = [UIDevice currentDevice];
	ua = [ua stringByAppendingString:@"_"];
	ua = [ua stringByAppendingString:_dev.systemName];
	ua = [ua stringByAppendingString:@"_"];
	ua = [ua stringByAppendingString:_dev.systemVersion];
	ua = [ua stringByAppendingString:@"_"];
	ua = [ua stringByAppendingString:_dev.model];
#endif
	[request addValue:ua forHTTPHeaderField:@"User-Agent"];

	if(method == HTTP_POST){
		NSData *req_data = [query dataUsingEncoding:NSUTF8StringEncoding];
		[request setHTTPBody:req_data];
		[request setHTTPMethod:@"POST"];
	}else{
		[request setHTTPMethod:@"GET"];
		if(query.length > 0){
			if([urlStr rangeOfString:@"?"].location != NSNotFound){
				urlStr = [NSString stringWithFormat:@"%@&%@", urlStr, query];
			}else{
				urlStr = [NSString stringWithFormat:@"%@?%@", urlStr, query];
			}
		}
	}
	
	NSURL *url = [NSURL URLWithString:urlStr];
	[request setURL:url];
	
	resp_cookies = nil;
	
#ifndef TARGET_OS_MAC
	[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
#endif
	[NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *urlresp, NSData *data, NSError *error){
#ifndef TARGET_OS_MAC
		[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
#endif
		NSHTTPURLResponse *response = (NSHTTPURLResponse *)urlresp;
		resp_cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:[response allHeaderFields]
															  forURL:[NSURL URLWithString:@""]];
		if(callback){
			dispatch_async(dispatch_get_main_queue(), ^{
				callback(data);
			});
		}
	}];
}

void http_get_raw(NSString *urlStr, id params, void (^callback)(NSData *data)){
	http_request_raw(urlStr, params, HTTP_GET, callback);
}

void http_post_raw(NSString *urlStr, id params, void (^callback)(NSData *data)){
	http_request_raw(urlStr, params, HTTP_POST, callback);
}

