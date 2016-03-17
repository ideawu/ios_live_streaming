//
//  LockingQueue.h
//  irtc
//
//  Created by ideawu on 3/17/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LockingQueue : NSObject

//- (NSUInteger)count;

/**
 push one to the back
 */
- (void)push:(id)item;
/**
 block until there is one in front, pop it out
 */
- (id)pop:(id)item;
/**
 block until there is one in front, obtain it, but not pop it out
 */
- (id)front;

@end
