//
//  DrcImage.m
//  CondensePNGs
//
//  Created by Markus Kirschner on 23.07.12.
//  Copyright (c) 2012 dressyco.de. All rights reserved.
//

#import "DrcImageLoader.h"

#ifdef __MAC_OS_X_VERSION_MAX_ALLOWED

@implementation NSImage(DrcAdditions)

+ (NSImage *)drc_imageFromBundleWithName:(NSString *)name
{
	NSImage *result = nil;
	
	if ([name pathExtension].length == 0) {
		name = [name stringByAppendingPathExtension:@"png"];
	}
	NSString *imagePath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:name];
	if (imagePath) {
		CGFloat scale = 1.0;
		CGImageRef imageRef = DrcLoadImage(imagePath, &scale);
		if (imageRef != NULL) {
			result = [[[NSImage alloc] initWithCGImage:imageRef size:NSZeroSize] autorelease];
		}
	}
	return result;
}

@end

#else

@implementation UIImage(DrcAdditions)

// Load image from the name bundle (no hidden caching like in imageNamed)
+ (UIImage *)drc_imageFromBundleWithName:(NSString *)name
{
	UIImage *result = nil;
	
	if ([name pathExtension].length == 0) {
		name = [name stringByAppendingPathExtension:@"png"];
	}
	NSString *imagePath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:name];
	if (imagePath) {
		CGFloat scale = 1.0;
		CGImageRef imageRef = DrcLoadImage(imagePath, &scale);
		if (imageRef != NULL) {
			result = [UIImage imageWithCGImage:imageRef scale:scale orientation:UIImageOrientationUp];
		}
	}
	return result;
}

@end

#endif

static CGContextRef createBitmapContextWithSize(CGSize size, BOOL alpha)
{
	size_t width = round(size.width);
	size_t height = round(size.height);
	size_t bytesPerRow = width * 4;
	CGImageAlphaInfo alphaInfo = alpha ? kCGImageAlphaPremultipliedLast : kCGImageAlphaNoneSkipLast;
	
	CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(NULL,
												 width,
												 height,
												 8,
												 bytesPerRow,
												 colorspace,
												 alphaInfo);
	CFRelease(colorspace);
	assert(context != NULL);
	return context;
}

static void releasePixels(void *info, const void *data, size_t size) 
{
	free((void*)data);
}

CGImageRef DrcCreateMaskedImageFromCondensedPNG(NSString *fileName)
{
	assert([[fileName pathExtension] isEqualToString:@"png"]);
	
	NSString *condensedFileName = [fileName stringByAppendingString:@"_condensed"];
	NSUInteger dataReadingOptions;
#ifdef __MAC_OS_X_VERSION_MAX_ALLOWED
	dataReadingOptions = NSDataReadingMapped;
#else
	dataReadingOptions = NSDataReadingMappedIfSafe;
#endif	
	// Reading the contents memory mapped is much better for overall memory usage
	NSData *data = [[NSData alloc] initWithContentsOfFile:condensedFileName options:dataReadingOptions error:nil];
	if (data == nil) {
		return NULL;
	}
	
	// Extract the length of the first part from the beginning
	CGImageRef result = NULL;
	uint32_t dataAlphaSize;
	uint16_t headerWidth, headerHeight;
	NSRange headerRange = NSMakeRange(0, sizeof(uint16_t));
	[data getBytes:&headerWidth range:headerRange];
	headerRange.location += headerRange.length;
	[data getBytes:&headerHeight range:headerRange];
	headerRange.location += headerRange.length;
	headerRange.length = sizeof(uint32_t);
	[data getBytes:&dataAlphaSize range:headerRange];
	
	NSRange alphaRange = NSMakeRange(headerRange.location+headerRange.length, dataAlphaSize);
	char *alphaBytes = malloc(dataAlphaSize);
	[data getBytes:alphaBytes range:alphaRange];
	
	CGDataProviderRef dataProviderAlpha = CGDataProviderCreateWithData(NULL, alphaBytes, dataAlphaSize, releasePixels);
	CGImageRef maskedImageRaw = CGImageCreateWithJPEGDataProvider(dataProviderAlpha, NULL, NO, kCGRenderingIntentDefault);
	CGDataProviderRelease(dataProviderAlpha);
	if (maskedImageRaw) {
		size_t width = CGImageGetWidth(maskedImageRaw);
		assert(width == headerWidth);
		size_t height = CGImageGetHeight(maskedImageRaw);
		assert(height == headerHeight);
		
		CGImageRef mask = CGImageMaskCreate(width, height,
											CGImageGetBitsPerComponent(maskedImageRaw),
											CGImageGetBitsPerPixel(maskedImageRaw),
											CGImageGetBytesPerRow(maskedImageRaw),
											CGImageGetDataProvider(maskedImageRaw), NULL, NO);
		
		
		CGImageRelease(maskedImageRaw);
		
		NSRange colorRange = NSMakeRange(alphaRange.location+dataAlphaSize, data.length-alphaRange.location-dataAlphaSize);
		char *colorBytes = malloc(colorRange.length);
		[data getBytes:colorBytes range:colorRange];
		
		CGDataProviderRef dataProviderColor = CGDataProviderCreateWithData(NULL, colorBytes, colorRange.length, releasePixels);
		CGImageRef colorImage = CGImageCreateWithJPEGDataProvider(dataProviderColor, NULL, NO, kCGRenderingIntentDefault);
		CGDataProviderRelease(dataProviderColor);
		
		CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
		CGContextRef offscreenContext = CGBitmapContextCreate(NULL, width, height, 8, 0, colorSpace, kCGImageAlphaPremultipliedFirst);
		if (offscreenContext != NULL) {
			CGRect rect = CGRectMake(0, 0, width, height);
			CGContextClipToMask(offscreenContext, rect, mask);
			CGContextDrawImage(offscreenContext, rect, colorImage);
			result = CGBitmapContextCreateImage(offscreenContext);
			
			CGContextRelease(offscreenContext);
		}
		CGImageRelease(colorImage);
		CGImageRelease(mask);
		
		CGColorSpaceRelease(colorSpace);
	}
	[data release];
	
	return result;
}

CGImageRef DrcLoadImage(NSString *imagePath, CGFloat *usedScale)
{
	CGImageRef result = NULL;
	
#ifndef __MAC_OS_X_VERSION_MAX_ALLOWED
	*usedScale = [UIScreen mainScreen].scale;
#endif
	
	if ([[imagePath pathExtension] isEqualToString:@"png"]) {
		// Try to load the condensed version of the PNG
		if (*usedScale == 2.0f) {
			NSString *originalFilePath = [NSString stringWithString:imagePath];
			NSString *fileName2x = [[[originalFilePath lastPathComponent] stringByDeletingPathExtension] stringByAppendingFormat:@"@2x.%@", [[originalFilePath lastPathComponent] pathExtension]];
			imagePath = [[originalFilePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:fileName2x];
			result = DrcCreateMaskedImageFromCondensedPNG(imagePath);
			if (result == NULL) {
				// No condensed @2x image present, use the original image
				imagePath = originalFilePath;
				*usedScale = 1.0f;
			}
		}
		
		if (result == NULL) {
			result = DrcCreateMaskedImageFromCondensedPNG(imagePath);
#ifndef __MAC_OS_X_VERSION_MAX_ALLOWED
			if (result == NULL) {
				*usedScale = [UIScreen mainScreen].scale;
			}
#endif			
		}
	}
	
	if (result == nil) {
		// Try to load the original image
		if (*usedScale == 2.0f) {
			NSFileManager *fileManager = [NSFileManager new];
			NSString *originalFilePath = [NSString stringWithString:imagePath];
			NSString *fileName2x = [[[originalFilePath lastPathComponent] stringByDeletingPathExtension] stringByAppendingFormat:@"@2x.%@", [[originalFilePath lastPathComponent] pathExtension]];
			imagePath = [[originalFilePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:fileName2x];
			if ([fileManager fileExistsAtPath:imagePath] == NO) {
				// No @2x image present, use the original image
				imagePath = originalFilePath;
				*usedScale = 1.0f;
				if ([fileManager fileExistsAtPath:imagePath] == NO) {
					// Invalid path
					imagePath = nil;
				}
			}
			[fileManager release];
		}
		
		if (imagePath) {
#ifndef __MAC_OS_X_VERSION_MAX_ALLOWED
			NSError *error = nil;
			UIImage *image = [UIImage imageWithData:[NSData dataWithContentsOfFile:imagePath options:NSDataReadingMappedIfSafe error:&error]];
			if (image != nil) {
				result = [image CGImage];
				[(id)result retain]; // UIImage is already autoreleased, so we need to retain the CGImageRef twice
			}
#else
			// Yes, it's really that complicated to load a CGImageRef!
			
			NSURL *imageURL = [NSURL fileURLWithPath:imagePath isDirectory:NO];
			CGImageSourceRef imageSource = CGImageSourceCreateWithURL((CFURLRef)imageURL, NULL);
			
			if (imageSource != NULL) {
				
				CGImageRef rawImage = CGImageSourceCreateImageAtIndex(imageSource, 0, NULL);
				CFRelease(imageSource);
				if (rawImage != NULL) {
					CGFloat rawImageWidth = CGImageGetWidth(rawImage);
					CGFloat rawImageHeight = CGImageGetHeight(rawImage);
					BOOL hasAlpha = NO;
					CGRect imageRect = CGRectMake(0, 0, rawImageWidth, rawImageHeight);
					CGImageSourceRef imageSource = CGImageSourceCreateWithURL((CFURLRef)imageURL, NULL);
					if (imageSource) {
						CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL);
						if (properties) {
							CFBooleanRef alpha = CFDictionaryGetValue(properties, kCGImagePropertyHasAlpha);
							hasAlpha = alpha != NULL && CFBooleanGetValue(alpha);
							CFRelease(properties);
						}
						CFRelease(imageSource);
					}
					
					CGContextRef context = createBitmapContextWithSize(imageRect.size, hasAlpha);
					CGContextSetBlendMode(context, kCGBlendModeCopy);
					CGContextDrawImage(context, imageRect, rawImage);
					CFRelease(rawImage);
					
					result = CGBitmapContextCreateImage(context);
					assert(result != NULL);
					CFRelease(context);
				}
			}
#endif
		}
	}
	
	if (result) {
		[[(id)result retain] autorelease];
	}

	return result;
}