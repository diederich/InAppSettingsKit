//
//	IASKSettingsReader.m
//	http://www.inappsettingskit.com
//
//	Copyright (c) 2009:
//	Luc Vandal, Edovia Inc., http://www.edovia.com
//	Ortwin Gentz, FutureTap GmbH, http://www.futuretap.com
//	All rights reserved.
// 
//	It is appreciated but not required that you give credit to Luc Vandal and Ortwin Gentz, 
//	as the original authors of this code. You can give credit in a blog post, a tweet or on 
//	a info page of your app. Also, the original authors appreciate letting them know if you use this code.
//
//	This code is licensed under the BSD license that is available at: http://www.opensource.org/licenses/bsd-license.php
//

#import "IASKSettingsReader.h"
#import "IASKSpecifier.h"

@interface IASKSettingsReader (private)
- (void)_reinterpretBundle:(NSDictionary*)settingsBundle;
- (BOOL)_sectionHasHeading:(NSInteger)section;
- (NSString *)platformSuffix;
- (NSString *)locateSettingsFile:(NSString *)file;

@end

@implementation IASKSettingsReader

@synthesize filterDelegate = _filterDelegate,
modelDelegate = _modelDelegate,
path=_path,
localizationTable=_localizationTable,
bundlePath=_bundlePath,
settingsBundle=_settingsBundle, 
dataSource=_dataSource,
hiddenKeys = _hiddenKeys;

- (id)init {
	return [self initWithFile:@"Root"];
}

- (id)initWithFile:(NSString*)file {
  return [self initWithFile:file filterDelegate:nil];
}

- (id)initWithFile:(NSString*)file filterDelegate:(id<IASKSettingsReaderFilterDelegate>) filterDelegate {
	if ((self = [super init])) {
    self.filterDelegate = filterDelegate;
		self.path = [self locateSettingsFile: file];
		[self setSettingsBundle:[NSDictionary dictionaryWithContentsOfFile:self.path]];
		self.bundlePath = [self.path stringByDeletingLastPathComponent];
		_bundle = [[NSBundle bundleWithPath:[self bundlePath]] retain];
		
		// Look for localization file
		self.localizationTable = [self.settingsBundle objectForKey:@"StringsTable"];
		if (!self.localizationTable)
		{
			// Look for localization file using filename
			self.localizationTable = [[[[self.path stringByDeletingPathExtension] // removes '.plist'
										stringByDeletingPathExtension] // removes potential '.inApp'
									   lastPathComponent] // strip absolute path
									  stringByReplacingOccurrencesOfString:[self platformSuffix] withString:@""]; // removes potential '~device' (~ipad, ~iphone)
			if([_bundle pathForResource:self.localizationTable ofType:@"strings"] == nil){
				// Could not find the specified localization: use default
				self.localizationTable = @"Root";
			}
		}

		if (_settingsBundle) {
			[self _reinterpretBundle:_settingsBundle];
		}
	}
	return self;
}

- (void)dealloc {
	[_path release], _path = nil;
	[_localizationTable release], _localizationTable = nil;
	[_bundlePath release], _bundlePath = nil;
	[_settingsBundle release], _settingsBundle = nil;
	[_dataSource release], _dataSource = nil;
	[_bundle release], _bundle = nil;
    [_hiddenKeys release], _hiddenKeys = nil;

	[super dealloc];
}


- (void)setHiddenKeys:(NSSet *)anHiddenKeys {
	if (_hiddenKeys != anHiddenKeys) {
		id old = _hiddenKeys;
		_hiddenKeys = [anHiddenKeys retain];
		[old release];
		
		if (_settingsBundle) {
			[self _reinterpretBundle:_settingsBundle];
		}
	}
}


- (void)_reinterpretBundle:(NSDictionary*)settingsBundle {
	NSArray *preferenceSpecifiers	= [settingsBundle objectForKey:kIASKPreferenceSpecifiers];
	NSInteger sectionCount			= -1;
	NSMutableArray *dataSource		= [[[NSMutableArray alloc] init] autorelease];
	
	for (NSDictionary *specifier in preferenceSpecifiers) {
		if ([[specifier objectForKey:kIASKType] isEqualToString:kIASKPSGroupSpecifier]) {
      if ([self.hiddenKeys containsObject:[specifier objectForKey:kIASKKey]]) {
        continue;
      }

      //optionally ask the delegate if this should be included
      if(nil != self.filterDelegate && ! [self.filterDelegate settingsReader:self shouldAddGroupTitleWithDictionary:specifier]) {
        continue;
      }

			NSMutableArray *newArray = [[NSMutableArray alloc] init];
			
			[newArray addObject:specifier];
			[dataSource addObject:newArray];
			[newArray release];
			sectionCount++;
		}
		else {
			if (sectionCount == -1) {
				NSMutableArray *newArray = [[NSMutableArray alloc] init];
				[dataSource addObject:newArray];
				[newArray release];
				sectionCount++;
			}
      
      IASKSpecifier *newSpecifier = [[[IASKSpecifier alloc] initWithSpecifier:specifier] autorelease];
      if(nil != self.filterDelegate && ! [self.filterDelegate settingsReader:self shouldAddSpecifier:newSpecifier]) {
        continue;
      }
      [[dataSource objectAtIndex:sectionCount] addObject:newSpecifier];
		}
	}
	[self setDataSource:dataSource];
}

- (BOOL)_sectionHasHeading:(NSInteger)section {
	return [[[[self dataSource] objectAtIndex:section] objectAtIndex:0] isKindOfClass:[NSDictionary class]];
}

- (NSInteger)numberOfSections {
	return [[self dataSource] count];
}

- (NSInteger)numberOfRowsForSection:(NSInteger)section {
	int headingCorrection = [self _sectionHasHeading:section] ? 1 : 0;
	return [(NSArray*)[[self dataSource] objectAtIndex:section] count] - headingCorrection;
}

- (IASKSpecifier*)specifierForIndexPath:(NSIndexPath*)indexPath {
	int headingCorrection = [self _sectionHasHeading:indexPath.section] ? 1 : 0;
	
	IASKSpecifier *specifier = [[[self dataSource] objectAtIndex:indexPath.section] objectAtIndex:(indexPath.row+headingCorrection)];
	specifier.settingsReader = self;
	return specifier;
}

- (NSIndexPath*)indexPathForKey:(NSString *)key {
	for (NSUInteger sectionIndex = 0; sectionIndex < self.dataSource.count; sectionIndex++) {
		NSArray *section = [self.dataSource objectAtIndex:sectionIndex];
		for (NSUInteger rowIndex = 0; rowIndex < section.count; rowIndex++) {
			IASKSpecifier *specifier = (IASKSpecifier*)[section objectAtIndex:rowIndex];
			if ([specifier isKindOfClass:[IASKSpecifier class]] && [specifier.key isEqualToString:key]) {
				NSUInteger correctedRowIndex = rowIndex - [self _sectionHasHeading:sectionIndex];
				return [NSIndexPath indexPathForRow:correctedRowIndex inSection:sectionIndex];
			}
		}
	}
	return nil;
}

- (IASKSpecifier*)specifierForKey:(NSString*)key {
	for (NSArray *specifiers in _dataSource) {
		for (id sp in specifiers) {
			if ([sp isKindOfClass:[IASKSpecifier class]]) {
				if ([[sp key] isEqualToString:key]) {
					return sp;
				}
			}
		}
	}
	return nil;
}

- (NSString*)titleForSection:(NSInteger)section {
	if ([self _sectionHasHeading:section]) {
		NSDictionary *dict = [[[self dataSource] objectAtIndex:section] objectAtIndex:kIASKSectionHeaderIndex];
		return [self titleForStringId:[dict objectForKey:kIASKTitle]];
	}
	return nil;
}

- (NSString*)keyForSection:(NSInteger)section {
	if ([self _sectionHasHeading:section]) {
		return [[[[self dataSource] objectAtIndex:section] objectAtIndex:kIASKSectionHeaderIndex] objectForKey:kIASKKey];
	}
	return nil;
}

- (NSString*)footerTextForSection:(NSInteger)section {
	if ([self _sectionHasHeading:section]) {
		NSDictionary *dict = [[[self dataSource] objectAtIndex:section] objectAtIndex:kIASKSectionHeaderIndex];
		return [self titleForStringId:[dict objectForKey:kIASKFooterText]];
	}
	return nil;
}

- (NSString*)titleForStringId:(NSString*)stringId {
	return [_bundle localizedStringForKey:stringId value:stringId table:self.localizationTable];
}

- (NSString*)pathForImageNamed:(NSString*)image {
	return [[self bundlePath] stringByAppendingPathComponent:image];
}

#define SETINGS_USE_ANIMATIONS 1

- (void) reload {
#ifdef SETINGS_USE_ANIMATIONS
  NSMutableArray* oldDataSource = [[self.dataSource mutableCopy] autorelease];
  [self _reinterpretBundle:self.settingsBundle];

  NSArray* newDataSource = self.dataSource;
  if([oldDataSource count] == [newDataSource count]) {
    //all good, return
    return;
  }
  [self.modelDelegate settingsReaderWillChangeContent:self];
  
  while ([oldDataSource count] > [newDataSource count]) {
    NSMutableArray* rowIndexPathsToRemove = [NSMutableArray array];
    NSMutableIndexSet* sectionsToRemove = [NSMutableIndexSet indexSet];
    NSUInteger currentSection = [oldDataSource count] - 1;
    [sectionsToRemove addIndex:currentSection];
    NSArray* sectionToRemove = [[[oldDataSource lastObject] retain] autorelease];
    [oldDataSource removeLastObject];
    NSUInteger counter = 0;
    for (id entry in sectionToRemove) {
      if([entry isKindOfClass:[NSDictionary class]]) {
        continue;
      }
      [rowIndexPathsToRemove addObject:
       [NSIndexPath indexPathForRow:counter inSection:currentSection]];
      ++counter;
    }
   
    for(NSIndexPath* indexPath in rowIndexPathsToRemove) {
      [self.modelDelegate settingsReader:self 
               didRemoveEntryAtIndexPath:indexPath];
    }
    [sectionsToRemove enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL* stop) {
      [self.modelDelegate settingsReader:self 
                        didRemoveSection:idx];      
    }];
  }

  if([oldDataSource count] < [newDataSource count]) {
    NSMutableArray* rowIndexPathsToAdd = [NSMutableArray array];
    NSMutableIndexSet* sectionsToAdd = [NSMutableIndexSet indexSet];

    //starting index
    NSUInteger startIndex = [oldDataSource count];
    for(unsigned int currentSectionIndex = startIndex; 
        currentSectionIndex < [newDataSource count]; 
        ++currentSectionIndex) {
      [sectionsToAdd addIndex:currentSectionIndex];
      NSArray* rowArrayToAdd = [newDataSource objectAtIndex:currentSectionIndex];
      NSUInteger counter = 0;
      for(id entry in rowArrayToAdd) {
        if([entry isKindOfClass:[NSDictionary class]]) {
          continue;
        }
        [rowIndexPathsToAdd addObject:[NSIndexPath indexPathForRow:counter 
                                                         inSection:currentSectionIndex]];
        ++counter;
      }
    }
    
    for(NSIndexPath* indexPath in rowIndexPathsToAdd) {
      [self.modelDelegate settingsReader:self 
                  didAddEntryAtIndexPath:indexPath];
    }
    [sectionsToAdd enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL* stop) {
      [self.modelDelegate settingsReader:self 
                           didAddSection:idx];      
    }];
  }
  [self.modelDelegate settingsReaderDidChangeContent:self];
#else 
  [self _reinterpretBundle:self.settingsBundle];
  [self.modelDelegate settingReaderChanged:self];
#endif
}

- (NSString *)platformSuffix {
	BOOL isPad = NO;
#if (__IPHONE_OS_VERSION_MAX_ALLOWED >= 30200)
	isPad = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;
#endif
	return isPad ? @"~ipad" : @"~iphone";
}

- (NSString *)file:(NSString *)file
		withBundle:(NSString *)bundle
			suffix:(NSString *)suffix
		 extension:(NSString *)extension {

	NSString *appBundle = [[NSBundle mainBundle] bundlePath];
	bundle = [appBundle stringByAppendingPathComponent:bundle];
	file = [file stringByAppendingFormat:@"%@%@", suffix, extension];
	return [bundle stringByAppendingPathComponent:file];

}

- (NSString *)locateSettingsFile: (NSString *)file {
	
	// The file is searched in the following order:
	//
	// InAppSettings.bundle/FILE~DEVICE.inApp.plist
	// InAppSettings.bundle/FILE.inApp.plist
	// InAppSettings.bundle/FILE~DEVICE.plist
	// InAppSettings.bundle/FILE.plist
	// Settings.bundle/FILE~DEVICE.inApp.plist
	// Settings.bundle/FILE.inApp.plist
	// Settings.bundle/FILE~DEVICE.plist
	// Settings.bundle/FILE.plist
	//
	// where DEVICE is either "iphone" or "ipad" depending on the current
	// interface idiom.
	//
	// Settings.app uses the ~DEVICE suffixes since iOS 4.0.  There are some
	// differences from this implementation:
	// - For an iPhone-only app running on iPad, Settings.app will not use the
	//	 ~iphone suffix.  There is no point in using these suffixes outside
	//	 of universal apps anyway.
	// - This implementation uses the device suffixes on iOS 3.x as well.
	// - also check current locale (short only)
	
	NSArray *bundles =
	[NSArray arrayWithObjects:kIASKBundleFolderAlt, kIASKBundleFolder, nil];
	
	NSArray *extensions =
	[NSArray arrayWithObjects:@".inApp.plist", @".plist", nil];
	
	NSArray *suffixes =
	[NSArray arrayWithObjects:[self platformSuffix], @"", nil];
	
	NSArray *languages =
	[NSArray arrayWithObjects:[[[NSLocale preferredLanguages] objectAtIndex:0] stringByAppendingString:KIASKBundleLocaleFolderExtension], @"", nil];
	
	NSString *path = nil;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	for (NSString *bundle in bundles) {
		for (NSString *extension in extensions) {
			for (NSString *suffix in suffixes) {
				for (NSString *language in languages) {
					path = [self file:file
						   withBundle:[bundle stringByAppendingPathComponent:language]
							   suffix:suffix
							extension:extension];
					if ([fileManager fileExistsAtPath:path]) {
						goto exitFromNestedLoop;
					}
				}
			}
		}
	}
	
exitFromNestedLoop:
	return path;
}

@end
