/*
 Copyright (c) 2014 ideawu. All rights reserved.
 Use of this source code is governed by a license that can be
 found in the LICENSE file.
 
 @author:  ideawu
 @website: http://www.cocoaui.com/
 */

#ifndef Http_h
#define Http_h

#import <Foundation/Foundation.h>

void http_get_raw(NSString *urlStr, id params, void (^callback)(NSData *data));
void http_post_raw(NSString *urlStr, id params, void (^callback)(NSData *data));

#endif
