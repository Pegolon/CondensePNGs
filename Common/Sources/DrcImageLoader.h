//
//  DrcImage.h
//  CondensePNGs
//
//  Created by Markus Kirschner on 23.07.12.
//  Copyright (c) 2012 dressyco.de. All rights reserved.
//

#ifdef __MAC_OS_X_VERSION_MAX_ALLOWED

@interface NSImage(DrcAdditions)

// Load image from the name bundle (no hidden caching like in imageNamed)
+ (NSImage *)drc_imageFromBundleWithName:(NSString *)name;

@end

#else

@interface UIImage(DrcAdditions)

// Load image from the name bundle (no hidden caching like in imageNamed)
+ (UIImage *)drc_imageFromBundleWithName:(NSString *)name;

@end

#endif

// The above categories use this function directly to load condensed PNGs
CGImageRef DrcLoadImage(NSString *imagePath, CGFloat *usedScale);
