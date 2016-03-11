//
//  inc.h
//  irtc
//
//  Created by ideawu on 3/11/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#ifndef inc_h
#define inc_h

#ifdef DEBUG
#	define log_debug(fmt, args...)	\
		NSLog((@"%@(%d): " fmt), [@(__FILE__) lastPathComponent],  __LINE__, ##args)
#else
#	define log_trace(...)
#endif

#endif /* inc_h */
