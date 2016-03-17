//
//  LockingQueue.m
//  irtc
//
//  Created by ideawu on 3/17/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "LockingQueue.h"

@interface LockingQueue(){
	NSMutableArray *_items;
	NSCondition *_condition;
}
@end

@implementation LockingQueue

- (id)init{
	self = [super init];
	_capacity = 128;
	return self;
}

- (id)initWithCapacity:(NSUInteger)capacity{
	self = [super init];
	_capacity = capacity;
	_items = [[NSMutableArray alloc] init];
	_condition = [[NSCondition alloc] init];
	return self;
}

- (NSUInteger)count{
	NSUInteger ret;
	[_condition lock];
	ret = _items.count;
	[_condition unlock];
	return ret;
}

- (void)push:(id)item{
	[_condition lock];
	{
		while(_items.count == _capacity){
			[_condition wait];
		}
		[_items addObject:item];
		[_condition signal];
	}
	[_condition unlock];
}

- (id)pop{
	id ret;
	[_condition lock];
	{
		while(_items.count == 0){
			[_condition wait];
		}
		ret = _items.firstObject;
		[_items removeObjectAtIndex:0];
		[_condition signal];
	}
	[_condition unlock];
	return ret;
}

- (id)front{
	id ret;
	[_condition lock];
	{
		while(_items.count == 0){
			[_condition wait];
		}
		ret = _items.firstObject;
	}
	[_condition unlock];
	return ret;
}

@end
