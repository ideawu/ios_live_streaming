//
//  ViewController.m
//  ios
//
//  Created by ideawu on 12/4/15.
//  Copyright © 2015 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import "ViewController.h"
#include "curl/curl.h"
#import "IKit/IKit.h"
#import "IObj/IObj.h"
#import "IObj/Text.h"
#import "LivePlayer.h"

@interface ViewController (){
	CURL *_curl;
}
@property IView *mainView;
@property IView *playerView;

@property CALayer *playerLayer;
@property LivePlayer *livePlayer;

- (void)streamCallback:(NSData *)data;
@end


// this function is called in a separated thread, it gets called when receive msg from icomet server
size_t icomet_callback(char *ptr, size_t size, size_t nmemb, void *userdata){
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
			
			ViewController *controller = (__bridge ViewController *)userdata;
			[controller streamCallback:data];
		}
	}
	if(sp != start){
		NSRange range = NSMakeRange(0, sp - start);
		[buf replaceBytesInRange:range withBytes:NULL length:0];
	}
	
	return sizeInBytes;
}

@implementation ViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.navigationController.navigationBar.translucent = NO;
	
	NSString *xml = @""
	"<div style=\"width: 100%; height: 100%; background: #fff;\">"
	"	<div id=\"player\" style=\"width: 340; height: 300; background: #ff3;\">"
	"	</div>"
	"	<p style=\"float: center; color: #333;\">Hello World!</p>"
	"</div>";
	_mainView = [IView viewFromXml:xml];
	_playerView = [_mainView getViewById:@"player"];
	[self.view addSubview:_mainView];
	
	[_mainView layoutIfNeeded];

	_playerLayer = [CALayer layer];
	[_playerLayer setFrame:[_playerView bounds]];
	[_playerLayer setBackgroundColor:[UIColor blackColor].CGColor];
	[_playerView.layer addSublayer:_playerLayer];
	
	_livePlayer = [LivePlayer playerWithCALayer:_playerLayer];
	[_livePlayer play];
	
	///////////////////////////
	[self performSelectorInBackground:@selector(startStreaming) withObject:nil];
}

- (void)startStreaming{
	_curl = curl_easy_init();
	curl_easy_setopt(_curl, CURLOPT_URL, "http://127.0.0.1:8100/stream?cname=&seq=1");
	curl_easy_setopt(_curl, CURLOPT_NOSIGNAL, 1L);	// try not to use signals
	curl_easy_setopt(_curl, CURLOPT_USERAGENT, curl_version());	// set a default user agent
	curl_easy_setopt(_curl, CURLOPT_WRITEFUNCTION, icomet_callback);
	curl_easy_setopt(_curl, CURLOPT_WRITEDATA, self);
	curl_easy_perform(_curl);
	curl_easy_cleanup(_curl);
}

// run in different thread(the curl thread)
- (void)streamCallback:(NSData *)data{
	IObj *obj = [[IObj alloc] initWithJSONData:data];
	NSString *type = obj.get(@"type").strval;
	NSString *content = obj.get(@"content").strval;
	NSLog(@"%7d byte(s), type: %@, content.len: %d", (int)data.length, type, (int)content.length);
	if([type isEqualToString:@"data"]){
		NSData *content_data = base64_decode(content);
		if(content_data){
			[self onStreamData:content_data];
		}else{
			NSLog(@"bad content");
		}
	}else{
		// TODO:
	}
}

- (void)onStreamData:(NSData *)data{
	[_livePlayer addMovieData:data originalPath:nil];
}

@end
