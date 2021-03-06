//
//  AppDelegate.m
//  recorder
//
//  Created by ideawu on 16-2-28.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import "AppDelegate.h"
#import "ViewController.h"

@interface AppDelegate (){
	UINavigationController *nav;
}
@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	log_debug(@"NSTemporaryDirectory: %@", NSTemporaryDirectory());

	self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	nav = [[UINavigationController alloc] init];
	nav.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: [UIColor blackColor]};
	nav.navigationBar.barTintColor = [UIColor whiteColor];
	nav.navigationBar.tintColor = [UIColor whiteColor];
	nav.navigationBar.translucent = NO;
	nav.view.backgroundColor = [UIColor groupTableViewBackgroundColor];
	[[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent];

	self.window.rootViewController = nav;
	[self.window makeKeyAndVisible];
	return YES;
}

- (void)start{
	log_debug(@"%s", __func__);
	UIViewController *controller = [[ViewController alloc] init];
	[nav pushViewController:controller animated:NO];
}

- (void)stop{
	log_debug(@"%s", __func__);
	[nav popViewControllerAnimated:NO];
}

- (void)applicationWillResignActive:(UIApplication *)application {
	// Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
	// Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
	// Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
	// If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
	[self stop];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
	// Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
	// Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
	[self start];
}

- (void)applicationWillTerminate:(UIApplication *)application {
	// Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

@end
