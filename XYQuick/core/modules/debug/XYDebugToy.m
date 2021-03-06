//
//  XYDebugToy.m
//  JoinShow
//
//  Created by heaven on 15/4/21.
//  Copyright (c) 2015年 Heaven. All rights reserved.
//

#import "XYDebugToy.h"
#import "XYRuntime.h"
#import <execinfo.h>
#import <objc/runtime.h>

#undef	XYDebug_key_hookDealloc
#define XYDebug_key_hookDealloc	"XYDebug.hookDealloc"

#pragma mark - XYDebugToy
@interface XYWatcher : NSObject
@property (nonatomic ,copy) NSString *stringDealloc;
@end

@implementation XYWatcher
- (void)dealloc
{
    NSLog(@"%@", _stringDealloc);
}
@end

@implementation XYDebugToy

+ (void)hookObject:(id)anObject whenDeallocLogString:(NSString *)string
{
    XYWatcher *watcher = [[XYWatcher alloc] init];
    watcher.stringDealloc = string;
    objc_setAssociatedObject(anObject, XYDebug_key_hookDealloc, watcher, OBJC_ASSOCIATION_RETAIN);
}

// Recursively travel down the view tree, increasing the indentation level for children
+ (void)dumpView:(UIView *)aView atIndent:(int)indent into:(NSMutableString *)outstring
{
    for (int i = 0; i < indent; i++) [outstring appendString:@"--"];
    
    [outstring appendFormat:@"[%2d] %@\n tag:%ld frame:%@\n", indent, [[aView class] description], (long)aView.tag, NSStringFromCGRect(aView.frame)];
    
    for (UIView *view in [aView subviews]) [self dumpView:view atIndent:indent + 1 into:outstring];
}
// Start the tree recursion at level 0 with the root view
+ (NSString *)displayViews:(UIView *)aView
{
    NSMutableString *outstring = [[NSMutableString alloc] init];
    [self dumpView:aView atIndent:0 into:outstring];
    return outstring;
}
@end



#pragma mark - XYDebug

#define K	(1024)
#define M	(K * 1024)
#define G	(M * 1024)

#undef	MAX_CALLSTACK_DEPTH
#define MAX_CALLSTACK_DEPTH	(64)

@interface XYDebug()

@property (nonatomic, readonly) int64_t				manualBytes;
@property (nonatomic, readonly) NSMutableArray *	manualBlocks;
@end

@implementation XYDebug __DEF_SINGLETON

+ (void)printCallstack:(NSUInteger)depth
{
    NSArray * callstack = [self callstack:depth];
    if ( callstack && callstack.count )
    {
        NSLog(@"%@", callstack);
    }
}
+ (NSArray *)callstack:(NSUInteger)depth
{
    NSMutableArray * array = [[NSMutableArray alloc] init];
    
    void * stacks[MAX_CALLSTACK_DEPTH] = { 0 };
    
    depth = backtrace( stacks, (int)((depth > MAX_CALLSTACK_DEPTH) ? MAX_CALLSTACK_DEPTH : depth) );
    if ( depth )
    {
        char ** symbols = backtrace_symbols( stacks, (int)depth );
        if ( symbols )
        {
            for ( int i = 0; i < depth; ++i )
            {
                NSString * symbol = [NSString stringWithUTF8String:(const char *)symbols[i]];
                if ( 0 == [symbol length] )
                    continue;
                
                NSRange range1 = [symbol rangeOfString:@"["];
                NSRange range2 = [symbol rangeOfString:@"]"];
                
                if ( range1.length > 0 && range2.length > 0 )
                {
                    NSRange range3;
                    range3.location = range1.location;
                    range3.length = range2.location + range2.length - range1.location;
                    [array addObject:[symbol substringWithRange:range3]];
                }
                else
                {
                    [array addObject:symbol];
                }
            }
            
            free( symbols );
        }
    }
    
    return array;
}

+ (void)breakPoint
{
#if defined(__ppc__)
    asm("trap");
#elif defined(__i386__) ||  defined(__amd64__)
    asm("int3");
#endif
}

- (void)allocAll
{
    NSProcessInfo *		progress = [NSProcessInfo processInfo];
    unsigned long long	total = [progress physicalMemory];
    //	NSUInteger			total = NSRealMemoryAvailable();
    
    for ( ;; )
    {
        if ( _manualBytes + 50 * M >= total )
            break;
        
        void * block = NSZoneCalloc( NSDefaultMallocZone(), 50, M );
        if ( nil == block )
        {
            block = NSZoneMalloc( NSDefaultMallocZone(), 50 * M );
        }
        
        if ( block )
        {
            _manualBytes += 50 * M;
            [_manualBlocks addObject:[NSNumber numberWithUnsignedLongLong:(unsigned long long)block]];
        }
        else
        {
            break;
        }
    }
}

- (void)freeAll
{
    for ( NSNumber * block in _manualBlocks )
    {
        void * ptr = (void *)[block unsignedLongLongValue];
        NSZoneFree( NSDefaultMallocZone(), ptr );
    }
    
    [_manualBlocks removeAllObjects];
}

- (void)alloc50M
{
    void * block = NSZoneCalloc( NSDefaultMallocZone(), 50, M );
    if ( nil == block )
    {
        block = NSZoneMalloc( NSDefaultMallocZone(), 50 * M );
    }
    
    if ( block )
    {
        _manualBytes += 50 * M;
        [_manualBlocks addObject:[NSNumber numberWithUnsignedLongLong:(unsigned long long)block]];
    }
}

- (void)free50M
{
    NSNumber * block = [_manualBlocks lastObject];
    if ( block )
    {
        void * ptr = (void *)[block unsignedLongLongValue];
        NSZoneFree( NSDefaultMallocZone(), ptr );
        
        [_manualBlocks removeLastObject];
    }
}


@end

#pragma mark - BorderView
#if (1 == __XY_DEBUG_SHOWBORDER__)
@interface UIWindow(XYDebugPrivate)
- (void)mySendEvent:(UIEvent *)event;
@end

@implementation UIWindow(XYDebug)

+ (void)load
{
    [XYRuntime swizzleInstanceMethodWithClass:[UIWindow class] originalSel:@selector(sendEvent:) replacementSel:@selector(mySendEvent:)];
}

- (void)mySendEvent:(UIEvent *)event
{
    UIWindow * keyWindow = [UIApplication sharedApplication].keyWindow;
    if ( self == keyWindow && UIEventTypeTouches == event.type)
    {
        NSSet * allTouches = [event allTouches];
        if ( 1 == [allTouches count] )
        {
            UITouch * touch = [[allTouches allObjects] objectAtIndex:0];
            if ( 1 == [touch tapCount]  && UITouchPhaseBegan == touch.phase )
            {
                // NSLog(@"view '%@', touch began\n%@", [[touch.view class] description], [touch.view description]);
                BorderView * border = [[BorderView alloc] initWithFrame:touch.view.bounds];
                [touch.view addSubview:border];
                [border startAnimation];
            }
        }
    }
    [self mySendEvent:event];
}

@end


@implementation BorderView
- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if ( self )
    {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.layer.borderWidth = 2.0f;
        self.layer.borderColor = [UIColor redColor].CGColor;
        //		self.textColor = [UIColor redColor];
        //		self.textAlignment = UITextAlignmentCenter;
        //		self.font = [UIFont boldSystemFontOfSize:12.0f];
    }
    return self;
}

- (void)didMoveToSuperview
{
    self.layer.cornerRadius = self.superview.layer.cornerRadius;
}

- (void)startAnimation
{
    self.alpha = 1.0f;
    
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationCurve:UIViewAnimationCurveLinear];
    [UIView setAnimationDuration:.75f];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationDidStopSelector:@selector(didAppearingAnimationStopped)];
    
    self.alpha = 0.0f;
    
    [UIView commitAnimations];
}

- (void)didAppearingAnimationStopped
{
    [self removeFromSuperview];
}

- (void)dealloc
{
}
@end

#endif




