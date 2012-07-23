//
//  DrcAppDelegate.m
//  CondensePNGs
//
//  Created by Markus Kirschner on 23.07.12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "DrcAppDelegate.h"
#import "DrcWindowController.h"

@implementation DrcAppDelegate

@synthesize window = _window;


- (void)dealloc
{
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	DrcWindowController *windowController = [[DrcWindowController alloc] initWithWindowNibName:@"DrcWindowController"];
	[windowController showWindow:nil];
}

@end
