//
//  DrcWindowController.m
//  CondensePNGs
//
//  Created by Markus Kirschner on 23.07.12.
//  Copyright (c) 2012 dressyco.de. All rights reserved.
//

#import "DrcWindowController.h"
#import "DrcImageLoader.h"

@implementation DrcWindowController

@synthesize imageView1 = _imageView1;
@synthesize imageView2 = _imageView2;
@synthesize imageView3 = _imageView3;
@synthesize imageView4 = _imageView4;
@synthesize imageView5 = _imageView5;

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
	self.imageView1.image = [NSImage drc_imageFromBundleWithName:@"lolcat1"];
	self.imageView2.image = [NSImage drc_imageFromBundleWithName:@"lolcat2"];
	self.imageView3.image = [NSImage drc_imageFromBundleWithName:@"lolcat3"];
	self.imageView4.image = [NSImage drc_imageFromBundleWithName:@"lolcat4"];
	self.imageView5.image = [NSImage drc_imageFromBundleWithName:@"earth"];
}

@end
