//
//  MKMapView.m
//  MapKit
//
//  Created by Rick Fillion on 7/11/10.
//  Copyright 2010 Centrix.ca. All rights reserved.
//

#import "MKMapView.h"
#import "JSON.h"
#import <MapKit/MKUserLocation.h>
#import "MKUserLocation+Private.h"
#import <MapKit/MKCircleView.h>
#import <MapKit/MKCircle.h>
#import <MapKit/MKPolyline.h>
#import <MapKit/MKPolygon.h>
#import <MapKit/MKAnnotationView.h>
#import <MapKit/MKPointAnnotation.h>

@interface MKMapView (Private)

// delegate wrappers
- (void)delegateRegionWillChangeAnimated:(BOOL)animated;
- (void)delegateRegionDidChangeAnimated:(BOOL)animated;
- (void)delegateDidUpdateUserLocation;
- (void)delegateDidFailToLocateUserWithError:(NSError *)error;
- (void)delegateWillStartLocatingUser;
- (void)delegateDidStopLocatingUser;
- (void)delegateDidAddOverlayViews:(NSArray *)overlayViews;
- (void)delegateDidAddAnnotationViews:(NSArray *)annotationViews;
- (void)delegateDidSelectAnnotationView:(MKAnnotationView *)view;
- (void)delegateDidDeselectAnnotationView:(MKAnnotationView *)view;
- (void)delegateAnnotationView:(MKAnnotationView *)annotationView didChangeDragState:(MKAnnotationViewDragState)newState fromOldState:(MKAnnotationViewDragState)oldState;

// WebView integration
- (void)setUserLocationMarkerVisible:(BOOL)visible;
- (void)updateUserLocationMarkerWithLocaton:(CLLocation *)location;
- (void)updateOverlayZIndexes;
- (void)annotationScriptObjectSelected:(WebScriptObject *)annotationScriptObject;
- (void)annotationScriptObjectDragStart:(WebScriptObject *)annotationScriptObject;
- (void)annotationScriptObjectDrag:(WebScriptObject *)annotationScriptObject;
- (void)annotationScriptObjectDragEnd:(WebScriptObject *)annotationScriptObject;
- (void)webviewReportingRegionChange;
- (CLLocationCoordinate2D)coordinateForAnnotationScriptObject:(WebScriptObject *)annotationScriptObject;

@end


@implementation MKMapView

@synthesize delegate, mapType, showsUserLocation;

+ (NSString *) webScriptNameForSelector:(SEL)sel
{
    NSString *name = nil;
    
    if (sel == @selector(annotationScriptObjectSelected:))
    {
        name = @"annotationScriptObjectSelected";
    }
    
    if (sel == @selector(webviewReportingRegionChange))
    {
        name = @"webviewReportingRegionChange";
    }
    
    if (sel == @selector(annotationScriptObjectDragStart:))
    {
        name = @"annotationScriptObjectDragStart";
    }
    
    if (sel == @selector(annotationScriptObjectDrag:))
    {
        name = @"annotationScriptObjectDrag";
    }
    
    if (sel == @selector(annotationScriptObjectDragEnd:))
    {
        name = @"annotationScriptObjectDragEnd";
    }
    
    return name;
}

+ (BOOL)isSelectorExcludedFromWebScript:(SEL)aSelector
{
    if (aSelector == @selector(annotationScriptObjectSelected:))
    {
        return NO;
    }
    
    if (aSelector == @selector(webviewReportingRegionChange))
    {
        return NO;
    }
    
    if (aSelector == @selector(annotationScriptObjectDragStart:))
    {
        return NO;
    }
    
    if (aSelector == @selector(annotationScriptObjectDrag:))
    {
        return NO;
    }
    
    if (aSelector == @selector(annotationScriptObjectDragEnd:))
    {
        return NO;
    }

    return YES;
}

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
        webView = [[WebView alloc] initWithFrame:[self bounds]];
        [webView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [webView setFrameLoadDelegate:self];
        
        // Create the overlay data structures
        overlays = [[NSMutableArray array] retain];
        overlayViews = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        overlayScriptObjects = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        
        // Create the annotation data structures
        annotations = [[NSMutableArray array] retain];
        selectedAnnotations = [[NSMutableArray array] retain];
        annotationViews = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        annotationScriptObjects = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        
        // TODO : make this suck less.
        NSBundle *frameworkBundle = [NSBundle bundleForClass:[self class]];
        NSString *indexPath = [frameworkBundle pathForResource:@"MapKit" ofType:@"html"];
        [[webView mainFrame] loadRequest:[NSURLRequest requestWithURL:[NSURL fileURLWithPath:indexPath]]]; 
        [[[webView mainFrame] frameView] setAllowsScrolling:NO];
        [self addSubview:webView];
        
        // Create a user location
        userLocation = [MKUserLocation new];
        
        // Get CoreLocation Manager
        locationManager = [CLLocationManager new];
        locationManager.delegate = self;
        locationManager.desiredAccuracy = kCLLocationAccuracyBest;
        
    }
    return self;
}

- (void)dealloc
{
    [webView removeFromSuperview];
    [webView release];
    [locationManager stopUpdatingLocation];
    [locationManager release];
    [userLocation release];
    [overlays release];
    CFRelease(overlayViews);
    overlayViews = NULL;
    CFRelease(overlayScriptObjects);
    overlayScriptObjects = NULL;
    [annotations release];
    [selectedAnnotations release];
    CFRelease(annotationViews);
    annotationViews = NULL;
    CFRelease(annotationScriptObjects);
    annotationScriptObjects = NULL;
    [super dealloc];
}

- (void)setFrame:(NSRect)frameRect
{
    [self delegateRegionWillChangeAnimated:NO];
    [super setFrame:frameRect];
    [self willChangeValueForKey:@"region"];
    [self didChangeValueForKey:@"region"];
    [self willChangeValueForKey:@"centerCoordinate"];
    [self didChangeValueForKey:@"centerCoordinate"];
    [self delegateRegionDidChangeAnimated:NO];
}

- (void)setMapType:(MKMapType)type
{
    mapType = type;
    WebScriptObject *webScriptObject = [webView windowScriptObject];
    NSArray *args = [NSArray arrayWithObject:[NSNumber numberWithInt:mapType]];
    [webScriptObject callWebScriptMethod:@"setMapType" withArguments:args];
}

- (CLLocationCoordinate2D)centerCoordinate
{
    WebScriptObject *webScriptObject = [webView windowScriptObject];
    NSString *json = [webScriptObject evaluateWebScript:@"getCenterCoordinate()"];
    NSDictionary *latlong = [json JSONValue];
    NSNumber *latitude = [latlong objectForKey:@"latitude"];
    NSNumber *longitude = [latlong objectForKey:@"longitude"];

    CLLocationCoordinate2D centerCoordinate;
    centerCoordinate.latitude = [latitude doubleValue];
    centerCoordinate.longitude = [longitude doubleValue];
    return centerCoordinate;
}

- (void)setCenterCoordinate:(CLLocationCoordinate2D)coordinate
{
    [self setCenterCoordinate:coordinate animated: NO];
}

- (void)setCenterCoordinate:(CLLocationCoordinate2D)coordinate animated:(BOOL)animated
{
    [self willChangeValueForKey:@"region"];
    NSArray *args = [NSArray arrayWithObjects:
                     [NSNumber numberWithDouble:coordinate.latitude],
                     [NSNumber numberWithDouble:coordinate.longitude],
                     [NSNumber numberWithBool:animated], 
                      nil];
    WebScriptObject *webScriptObject = [webView windowScriptObject];
    [webScriptObject callWebScriptMethod:@"setCenterCoordinateAnimated" withArguments:args];
    [self didChangeValueForKey:@"region"];
    hasSetCenterCoordinate = YES;
}


- (MKCoordinateRegion)region
{
    WebScriptObject *webScriptObject = [webView windowScriptObject];
    NSString *json = [webScriptObject evaluateWebScript:@"getRegion()"];
    NSDictionary *regionDict = [json JSONValue];
    
    NSNumber *centerLatitude = [regionDict valueForKeyPath:@"center.latitude"];
    NSNumber *centerLongitude = [regionDict valueForKeyPath:@"center.longitude"];
    NSNumber *latitudeDelta = [regionDict objectForKey:@"latitudeDelta"];
    NSNumber *longitudeDelta = [regionDict objectForKey:@"longitudeDelta"];
    
    MKCoordinateRegion region;
    region.center.longitude = [centerLongitude doubleValue];
    region.center.latitude = [centerLatitude doubleValue];
    region.span.latitudeDelta = [latitudeDelta doubleValue];
    region.span.longitudeDelta = [longitudeDelta doubleValue];
    return region;
}

- (void)setRegion:(MKCoordinateRegion)region
{
    [self setRegion:region animated: NO];
}

- (void)setRegion:(MKCoordinateRegion)region animated:(BOOL)animated
{
    [self delegateRegionWillChangeAnimated:animated];
    [self willChangeValueForKey:@"centerCoordinate"];
    WebScriptObject *webScriptObject = [webView windowScriptObject];
    NSArray *args = [NSArray arrayWithObjects:
                     [NSNumber numberWithDouble:region.center.latitude], 
                     [NSNumber numberWithDouble:region.center.longitude], 
                     [NSNumber numberWithDouble:region.span.latitudeDelta], 
                     [NSNumber numberWithDouble:region.span.longitudeDelta],
                     [NSNumber numberWithBool:animated], 
                     nil];
    [webScriptObject callWebScriptMethod:@"setRegionAnimated" withArguments:args];
    [self didChangeValueForKey:@"centerCoordinate"];
    [self delegateRegionDidChangeAnimated:animated];
}

- (void)setShowsUserLocation:(BOOL)show
{
    if (show == showsUserLocation)
        return;
    showsUserLocation = show;
    if (showsUserLocation)
    {
        [userLocation _setUpdating:YES];
        [locationManager startUpdatingLocation];
    }
    else 
    {
        [self setUserLocationMarkerVisible: NO];
        [userLocation _setUpdating:NO];
        [locationManager stopUpdatingLocation];
        [userLocation _setLocation:nil];
    }
}

- (BOOL)isUserLocationVisible
{
    if (!self.showsUserLocation || !userLocation.location)
        return NO;
    WebScriptObject *webScriptObject = [webView windowScriptObject];
    NSNumber *visible = [webScriptObject callWebScriptMethod:@"isUserLocationVisible" withArguments:[NSArray array]];
    return [visible boolValue];
}

#pragma mark Overlays

- (NSArray *)overlays
{
    return [[overlays copy] autorelease];
}

- (void)addOverlay:(id < MKOverlay >)overlay
{
    [self insertOverlay:overlay atIndex:[overlays count]];
}

- (void)addOverlays:(NSArray *)someOverlays
{
    for (id<MKOverlay>overlay in someOverlays)
    {
        [self addOverlay: overlay];
    }
}

- (void)exchangeOverlayAtIndex:(NSUInteger)index1 withOverlayAtIndex:(NSUInteger)index2
{
    if (index1 >= [overlays count] || index2 >= [overlays count])
    {
        NSLog(@"exchangeOverlayAtIndex: either index1 or index2 is above the bounds of the overlays array.");
        return;
    }
    
    id < MKOverlay > overlay1 = [[overlays objectAtIndex: index1] retain];
    id < MKOverlay > overlay2 = [[overlays objectAtIndex: index2] retain];
    [overlays replaceObjectAtIndex:index2 withObject:overlay1];
    [overlays replaceObjectAtIndex:index1 withObject:overlay2];
    [overlay1 release];
    [overlay2 release];
    [self updateOverlayZIndexes];
}

- (void)insertOverlay:(id < MKOverlay >)overlay aboveOverlay:(id < MKOverlay >)sibling
{
    if (![overlays containsObject:sibling])
        return;
    
    NSUInteger indexOfSibling = [overlays indexOfObject:sibling];
    [self insertOverlay:overlay atIndex: indexOfSibling+1];
}

- (void)insertOverlay:(id < MKOverlay >)overlay atIndex:(NSUInteger)index
{
    // check if maybe we already have this one.
    if ([overlays containsObject:overlay])
        return;
    
    // Make sure we have a valid index.
    if (index > [overlays count])
        index = [overlays count];
    
    WebScriptObject *webScriptObject = [webView windowScriptObject];
    
    MKOverlayView *overlayView = nil;
    if ([self.delegate respondsToSelector:@selector(mapView:viewForOverlay:)])
        overlayView = [self.delegate mapView:self viewForOverlay:overlay];
    if (!overlayView)
    {
        // TODO: Handle the case where we have no view
        NSLog(@"Wasn't able to create a MKOverlayView for overlay: %@", overlay);
        return;
    }
    
    WebScriptObject *overlayScriptObject = [overlayView overlayScriptObjectFromMapSriptObject:webScriptObject];
    
    [overlays insertObject:overlay atIndex:index];
    CFDictionarySetValue(overlayViews, overlay, overlayView);
    CFDictionarySetValue(overlayScriptObjects, overlay, overlayScriptObject);
    
    NSArray *args = [NSArray arrayWithObject:overlayScriptObject];
    [webScriptObject callWebScriptMethod:@"addOverlay" withArguments:args];
    [overlayView draw:overlayScriptObject];
    
    [self updateOverlayZIndexes];
    
    // TODO: refactor how this works so that we can send one batch call
    // when they called addOverlays:
    [self delegateDidAddOverlayViews:[NSArray arrayWithObject:overlayView]];
}

- (void)insertOverlay:(id < MKOverlay >)overlay belowOverlay:(id < MKOverlay >)sibling
{
    if (![overlays containsObject:sibling])
        return;
    
    NSUInteger indexOfSibling = [overlays indexOfObject:sibling];
    [self insertOverlay:overlay atIndex: indexOfSibling];    
}

- (void)removeOverlay:(id < MKOverlay >)overlay
{
    if (![overlays containsObject:overlay])
        return;
    
    WebScriptObject *webScriptObject = [webView windowScriptObject];
    WebScriptObject *overlayScriptObject = (WebScriptObject *)CFDictionaryGetValue(overlayScriptObjects, overlay);
    NSArray *args = [NSArray arrayWithObject:overlayScriptObject];
    [webScriptObject callWebScriptMethod:@"removeOverlay" withArguments:args];

    CFDictionaryRemoveValue(overlayViews, overlay);
    CFDictionaryRemoveValue(overlayScriptObjects, overlay);

    [overlays removeObject:overlay];
    [self updateOverlayZIndexes];
}

- (void)removeOverlays:(NSArray *)someOverlays
{
    for (id<MKOverlay>overlay in someOverlays)
    {
        [self removeOverlay: overlay];
    }
}

- (MKOverlayView *)viewForOverlay:(id < MKOverlay >)overlay
{
    if (![overlays containsObject:overlay])
        return nil;
    return (MKOverlayView *)CFDictionaryGetValue(overlayViews, overlay);
}

#pragma mark Annotations

- (NSArray *)annotations
{
    return [[annotations copy] autorelease];
}

- (void)addAnnotation:(id < MKAnnotation >)annotation
{
    // check if maybe we already have this one.
    if ([annotations containsObject:annotation])
        return;
    WebScriptObject *webScriptObject = [webView windowScriptObject];
    
    MKAnnotationView *annotationView = nil;
    if ([self.delegate respondsToSelector:@selector(mapView:viewForAnnotation:)])
        annotationView = [self.delegate mapView:self viewForAnnotation:annotation];
    if (!annotationView)
    {
        // TODO: Handle the case where we have no view
        NSLog(@"Wasn't able to create a MKAnnotationView for annotation: %@", annotation);
        return;
    }
    
    WebScriptObject *annotationScriptObject = [annotationView overlayScriptObjectFromMapSriptObject:webScriptObject];
    
    [annotations addObject:annotation];
    CFDictionarySetValue(annotationViews, annotation, annotationView);
    CFDictionarySetValue(annotationScriptObjects, annotation, annotationScriptObject);
    
    NSArray *args = [NSArray arrayWithObject:annotationScriptObject];
    [webScriptObject callWebScriptMethod:@"addAnnotation" withArguments:args];
    [annotationView draw:annotationScriptObject];
    
    // TODO: refactor how this works so that we can send one batch call
    // when they called addAnnotations:
    [self delegateDidAddAnnotationViews:[NSArray arrayWithObject:annotationView]];
}

- (void)addAnnotations:(NSArray *)someAnnotations
{
    for (id<MKAnnotation>annotation in someAnnotations)
    {
        [self addAnnotation: annotation];
    }
}

- (void)removeAnnotation:(id < MKAnnotation >)annotation
{
    if (![annotations containsObject:annotation])
        return;
    
    WebScriptObject *webScriptObject = [webView windowScriptObject];
    WebScriptObject *annotationScriptObject = (WebScriptObject *)CFDictionaryGetValue(annotationScriptObjects, annotation);
    NSArray *args = [NSArray arrayWithObject:annotationScriptObject];
    [webScriptObject callWebScriptMethod:@"removeAnnotation" withArguments:args];
    
    CFDictionaryRemoveValue(annotationViews, annotation);
    CFDictionaryRemoveValue(annotationScriptObjects, annotation);
    
    [annotations removeObject:annotation];
}

- (void)removeAnnotations:(NSArray *)someAnnotations
{
    for (id<MKAnnotation>annotation in someAnnotations)
    {
        [self removeAnnotation: annotation];
    }
}

- (MKAnnotationView *)viewForAnnotation:(id < MKAnnotation >)annotation
{
    if (![annotations containsObject:annotation])
        return nil;
    return (MKAnnotationView *)CFDictionaryGetValue(annotationViews, annotation);
}

- (MKAnnotationView *)dequeueReusableAnnotationViewWithIdentifier:(NSString *)identifier
{
    // Unsupported for now.
    return nil; 
}

- (void)selectAnnotation:(id < MKAnnotation >)annotation animated:(BOOL)animated
{
    if ([selectedAnnotations containsObject:annotation])
        return;
    // TODO : probably want to do something here...
    id view = CFDictionaryGetValue(annotationViews, annotation);
    [self delegateDidSelectAnnotationView:view];
    [selectedAnnotations addObject:annotation];
}

- (void)deselectAnnotation:(id < MKAnnotation >)annotation animated:(BOOL)animated
{
    // TODO : animate this if called for.
    if (![selectedAnnotations containsObject:annotation])
        return;
    // TODO : probably want to do something here...
    id view = CFDictionaryGetValue(annotationViews, annotation);
    [self delegateDidDeselectAnnotationView:view];
    [selectedAnnotations removeObject:annotation];
}

- (NSArray *)selectedAnnotations
{
    return [[selectedAnnotations copy] autorelease];
}

- (void)setSelectedAnnotations:(NSArray *)someAnnotations
{
    // Deselect whatever was selected
    NSArray *oldSelectedAnnotations = [self selectedAnnotations];
    for (id <MKAnnotation> annotation in oldSelectedAnnotations)
    {
        [self deselectAnnotation:annotation animated:NO];
    }
    NSMutableArray *newSelectedAnnotations = [NSMutableArray arrayWithArray: [[someAnnotations copy] autorelease]];
    [selectedAnnotations release];
    selectedAnnotations = [newSelectedAnnotations retain];
    
    // If it's manually set and there's more than one, you only select the first according to the docs.
    if ([selectedAnnotations count] > 0)
        [self selectedAnnotation:[selectedAnnotations objectAtIndex:0] animated:NO];
}

#pragma mark Faked Properties

- (BOOL)isScrollEnabled
{
    return YES;
}

- (void)setScrollEnabled:(BOOL)scrollEnabled
{
    if (!scrollEnabled)
        NSLog(@"setting scrollEnabled to NO on MKMapView not supported.");
}

- (BOOL)isZoomEnabled
{
    return YES;
}

- (void)setZoomEnabled:(BOOL)zoomEnabled
{
    if (!zoomEnabled)
        NSLog(@"setting zoomEnabled to NO on MKMapView not supported");
}



#pragma mark CoreLocationManagerDelegate

- (void) locationManager: (CLLocationManager *)manager
     didUpdateToLocation: (CLLocation *)newLocation
            fromLocation: (CLLocation *)oldLocation
{
    if (!hasSetCenterCoordinate)
        [self setCenterCoordinate:newLocation.coordinate];
    [userLocation _setLocation:newLocation];
    [self updateUserLocationMarkerWithLocaton:newLocation];
    [self setUserLocationMarkerVisible:YES];
    [self delegateDidUpdateUserLocation];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    [self delegateDidFailToLocateUserWithError:error];
    [self setUserLocationMarkerVisible:NO];
}

#pragma mark WebFrameLoadDelegate

- (void)webView:(WebView *)sender didClearWindowObject:(WebScriptObject *)windowScriptObject forFrame:(WebFrame *)frame
{
    [windowScriptObject setValue:windowScriptObject forKey:@"WindowScriptObject"];
    [windowScriptObject setValue:self forKey:@"MKMapView"];
}


- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    // CoreLocation can sometimes trigger before the page has even finished loading.
    if (self.showsUserLocation && userLocation.location)
    {
        [self locationManager: locationManager didUpdateToLocation: userLocation.location fromLocation:nil];
    }
    
    CLLocationCoordinate2D coord;
    coord.latitude = 49.84770356304121;
    coord.longitude = -97.1728089768459;

    CLLocationCoordinate2D coords[3];
    coords[0].latitude = 49.83770356304121;
    coords[0].longitude = -97.1628089768459;
    coords[1].latitude = 49.86770356304121;
    coords[1].longitude = -97.1628089768459;
    coords[2].latitude = 49.86770356304121;
    coords[2].longitude = -97.2028089768459;
    
    CLLocationCoordinate2D innerCoords[3];
    innerCoords[0].latitude = 49.85070356304121;
    innerCoords[0].longitude = -97.1758089768459;
    innerCoords[1].latitude = 49.85470356304121;
    innerCoords[1].longitude = -97.1758089768459;
    innerCoords[2].latitude = 49.85470356304121;
    innerCoords[2].longitude = -97.1828089768459;
    /*
    MKCircle *circle1 = [MKCircle circleWithCenterCoordinate:coord radius: 400];
    MKCircle *circle2 = [MKCircle circleWithCenterCoordinate:coords[0] radius: 400];
    MKCircle *circle3 = [MKCircle circleWithCenterCoordinate:coords[1] radius: 400];
    MKCircle *circle4 = [MKCircle circleWithCenterCoordinate:coords[2] radius: 400];
    MKCircle *circle5 = [MKCircle circleWithCenterCoordinate:innerCoords[0] radius: 400];
    MKCircle *circle6 = [MKCircle circleWithCenterCoordinate:innerCoords[1] radius: 400];
    MKCircle *circle7 = [MKCircle circleWithCenterCoordinate:innerCoords[2] radius: 400];

    NSLog(@"start: %@", [self overlays]);
    [self insertOverlay:circle1 atIndex:0];
    NSLog(@"1: %@", [self overlays]);
    [self insertOverlay:circle2 atIndex:1];
    NSLog(@"2: %@", [self overlays]);
    [self insertOverlay:circle3 atIndex:1];
    NSLog(@"3: %@", [self overlays]);
    [self insertOverlay:circle4 atIndex:1];
    NSLog(@"4: %@", [self overlays]);
    [self insertOverlay:circle5 aboveOverlay:circle1];
    NSLog(@"5: %@", [self overlays]);
    [self insertOverlay:circle6 belowOverlay:circle1];
    NSLog(@"6: %@", [self overlays]);
    [self removeOverlay:circle1];

    MKPointAnnotation *pointAnnotation = [[[MKPointAnnotation alloc] init] autorelease];
    pointAnnotation.coordinate = coord;
    pointAnnotation.title = @"Some Title";
    [self addAnnotation:pointAnnotation];
    MKPointAnnotation *pointAnnotation2 = [[[MKPointAnnotation alloc] init] autorelease];
    pointAnnotation2.coordinate = coords[0];
    pointAnnotation2.title = @"Another Title";
    [self addAnnotation:pointAnnotation2];
    */
    
    //MKPolyline *polyline = [MKPolyline polylineWithCoordinates:coords count:3];
    //MKPolygon *innerPolygon = [MKPolygon polygonWithCoordinates:innerCoords count:3];
    //MKPolygon *polygon = [MKPolygon polygonWithCoordinates:coords count:3 interiorPolygons:[NSArray arrayWithObject:innerPolygon]];

    //[self addOverlay: polygon];
}


#pragma mark Private Delegate Wrappers

- (void)delegateRegionWillChangeAnimated:(BOOL)animated
{
    if (delegate && [delegate respondsToSelector:@selector(mapView:regionWillChangeAnimated:)])
    {
        [delegate mapView:self regionWillChangeAnimated:animated];
    }
}

- (void)delegateRegionDidChangeAnimated:(BOOL)animated
{
    if (delegate && [delegate respondsToSelector:@selector(mapView:regionDidChangeAnimated:)])
    {
        [delegate mapView:self regionDidChangeAnimated:animated];
    }
}

- (void)delegateDidUpdateUserLocation
{
    if (delegate && [delegate respondsToSelector:@selector(mapView:didUpdateUserLocation:)])
    {
        [delegate mapView:self didUpdateUserLocation:userLocation];
    }
}

- (void)delegateDidFailToLocateUserWithError:(NSError *)error
{
    if (delegate && [delegate respondsToSelector:@selector(mapView:didFailToLocateUserWithError:)])
    {
        [delegate mapView:self didFailToLocateUserWithError:error];
    }
}

- (void)delegateWillStartLocatingUser
{
    if (delegate && [delegate respondsToSelector:@selector(mapViewWillStartLocatingUser:)])
    {
        [delegate mapViewWillStartLocatingUser:self];
    }
}

- (void)delegateDidStopLocatingUser
{
    if (delegate && [delegate respondsToSelector:@selector(mapViewDidStopLocatingUser:)])
    {
        [delegate mapViewDidStopLocatingUser:self];
    }
}

- (void)delegateDidAddOverlayViews:(NSArray *)someOverlayViews
{
    if (delegate && [delegate respondsToSelector:@selector(mapView:didAddOverlayViews:)])
    {
        [delegate mapView:self didAddOverlayViews:someOverlayViews];
    }
}

- (void)delegateDidAddAnnotationViews:(NSArray *)someAnnotationViews
{
    if (delegate && [delegate respondsToSelector:@selector(mapView:didAddAnnotationViews:)])
    {
        [delegate mapView:self didAddAnnotationViews:someAnnotationViews];
    }
}

- (void)delegateDidSelectAnnotationView:(MKAnnotationView *)view
{
    if (delegate && [delegate respondsToSelector:@selector(mapView:didSelectAnnotationView:)])
    {
        [delegate mapView:self didSelectAnnotationView:view];
    }
}

- (void)delegateDidDeselectAnnotationView:(MKAnnotationView *)view
{
    if (delegate && [delegate respondsToSelector:@selector(mapView:didDeselectAnnotationView:)])
    {
        [delegate mapView:self didDeselectAnnotationView:view];
    }
}

- (void)delegateAnnotationView:(MKAnnotationView *)annotationView 
            didChangeDragState:(MKAnnotationViewDragState)newState 
                  fromOldState:(MKAnnotationViewDragState)oldState
{
    if (delegate && [delegate respondsToSelector:@selector(mapView:annotationView:didChangeDragState:fromOldState:)])
    {
        [delegate mapView:self annotationView:annotationView didChangeDragState:newState fromOldState:oldState];
    }
}

#pragma mark Private WebView Integration

- (void)setUserLocationMarkerVisible:(BOOL)visible
{
    NSArray *args = [NSArray arrayWithObjects:
                     [NSNumber numberWithBool:visible], 
                     nil];
    WebScriptObject *webScriptObject = [webView windowScriptObject];
    [webScriptObject callWebScriptMethod:@"setUserLocationVisible" withArguments:args];
    //NSLog(@"calling setUserLocationVisible with %@", args);
}

- (void)updateUserLocationMarkerWithLocaton:(CLLocation *)location
{
    WebScriptObject *webScriptObject = [webView windowScriptObject];

    CLLocationAccuracy accuracy = MAX(location.horizontalAccuracy, location.verticalAccuracy);
    NSArray *args = [NSArray arrayWithObjects:
                     [NSNumber numberWithDouble: accuracy], 
                     nil];
    [webScriptObject callWebScriptMethod:@"setUserLocationRadius" withArguments:args];
    //NSLog(@"calling setUserLocationRadius with %@", args);
    args = [NSArray arrayWithObjects:
            [NSNumber numberWithDouble:location.coordinate.latitude],
            [NSNumber numberWithDouble:location.coordinate.longitude],
            nil];
    [webScriptObject callWebScriptMethod:@"setUserLocationLatitudeLongitude" withArguments:args];
    //NSLog(@"caling setUserLocationLatitudeLongitude with %@", args);
}

- (void)updateOverlayZIndexes
{
    //NSLog(@"updating overlay z indexes of :%@", overlays);
    NSUInteger zIndex = 4000; // some arbitrary starting value
    WebScriptObject *webScriptObject = [webView windowScriptObject];
    for (id <MKOverlay> overlay in overlays)
    {
        WebScriptObject *overlayScriptObject = (WebScriptObject *)CFDictionaryGetValue(overlayScriptObjects, overlay);
        if (overlayScriptObject)
        {
            NSArray *args = [NSArray arrayWithObjects: overlayScriptObject, @"zIndex", [NSNumber numberWithInteger:zIndex], nil];
            [webScriptObject callWebScriptMethod:@"setOverlayOption" withArguments:args];
        }
        zIndex++;
    }
}

- (void)annotationScriptObjectSelected:(WebScriptObject *)annotationScriptObject
{
    // Deselect everything that was selected
    [self setSelectedAnnotations:[NSArray array]];
    
    for (id <MKAnnotation> annotation in annotations)
    {
        WebScriptObject *scriptObject = (WebScriptObject *)CFDictionaryGetValue(annotationScriptObjects, annotation);
        if ([scriptObject isEqual:annotationScriptObject])
        {
            [self selectAnnotation:annotation animated:NO];
        }
    }
}

- (void)annotationScriptObjectDragStart:(WebScriptObject *)annotationScriptObject
{
    //NSLog(@"annotationScriptObjectDragStart:");
    for (id <MKAnnotation> annotation in annotations)
    {
        WebScriptObject *scriptObject = (WebScriptObject *)CFDictionaryGetValue(annotationScriptObjects, annotation);
        if ([scriptObject isEqual:annotationScriptObject])
        {
            MKAnnotationView *view = (MKAnnotationView *)CFDictionaryGetValue(annotationViews, annotation);
            // it has to be an annotation that actually supports moving.
            if ([annotation respondsToSelector:@selector(setCoordinate:)])
            {
                view.dragState = MKAnnotationViewDragStateStarting;
                [self delegateAnnotationView:view didChangeDragState:MKAnnotationViewDragStateStarting fromOldState:MKAnnotationViewDragStateNone];
            }
        }
    }
}

- (void)annotationScriptObjectDrag:(WebScriptObject *)annotationScriptObject
{
    //NSLog(@"annotationScriptObjectDrag:");
    for (id <MKAnnotation> annotation in annotations)
    {
        WebScriptObject *scriptObject = (WebScriptObject *)CFDictionaryGetValue(annotationScriptObjects, annotation);
        if ([scriptObject isEqual:annotationScriptObject])
        {
            MKAnnotationView *view = (MKAnnotationView *)CFDictionaryGetValue(annotationViews, annotation);
            // it has to be an annotation that actually supports moving.
            if ([annotation respondsToSelector:@selector(setCoordinate:)])
            {
                CLLocationCoordinate2D newCoordinate = [self coordinateForAnnotationScriptObject:annotationScriptObject];
                [annotation setCoordinate:newCoordinate];
                if (view.dragState != MKAnnotationViewDragStateDragging)
                {
                    view.dragState = MKAnnotationViewDragStateNone;
                    [self delegateAnnotationView:view didChangeDragState:MKAnnotationViewDragStateDragging fromOldState:MKAnnotationViewDragStateStarting];
                }
            }
        }
    }
}

- (void)annotationScriptObjectDragEnd:(WebScriptObject *)annotationScriptObject
{
    //NSLog(@"annotationScriptObjectDragEnd");
    for (id <MKAnnotation> annotation in annotations)
    {
        WebScriptObject *scriptObject = (WebScriptObject *)CFDictionaryGetValue(annotationScriptObjects, annotation);
        if ([scriptObject isEqual:annotationScriptObject])
        {
            MKAnnotationView *view = (MKAnnotationView *)CFDictionaryGetValue(annotationViews, annotation);
            // it has to be an annotation that actually supports moving.
            if ([annotation respondsToSelector:@selector(setCoordinate:)])
            {
                CLLocationCoordinate2D newCoordinate = [self coordinateForAnnotationScriptObject:annotationScriptObject];
                [annotation setCoordinate:newCoordinate];
                view.dragState = MKAnnotationViewDragStateNone;
                [self delegateAnnotationView:view didChangeDragState:MKAnnotationViewDragStateNone fromOldState:MKAnnotationViewDragStateDragging];
            }
        }
    }
}

- (void)webviewReportingRegionChange
{
    [self delegateRegionDidChangeAnimated:NO];
    [self willChangeValueForKey:@"centerCoordinate"];
    [self didChangeValueForKey:@"centerCoordinate"];
    [self willChangeValueForKey:@"region"];
    [self didChangeValueForKey:@"region"];
}

- (CLLocationCoordinate2D)coordinateForAnnotationScriptObject:(WebScriptObject *)annotationScriptObject
{
    CLLocationCoordinate2D coord;
    coord.latitude = 0.0;
    coord.longitude = 0.0;
    WebScriptObject *windowScriptObject = [webView windowScriptObject];
    
    NSString *json = [windowScriptObject callWebScriptMethod:@"coordinateForAnnotation" withArguments:[NSArray arrayWithObject:annotationScriptObject]];
    NSDictionary *latlong = [json JSONValue];
    NSNumber *latitude = [latlong objectForKey:@"latitude"];
    NSNumber *longitude = [latlong objectForKey:@"longitude"];
    
    coord.latitude = [latitude doubleValue];
    coord.longitude = [longitude doubleValue];
    
    return coord;
}

@end