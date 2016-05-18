/*
 https://github.com/waynezxcv/Gallop

 Copyright (c) 2016 waynezxcv <liuweiself@126.com>

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 */


#import "LWTextLayout.h"
#import "LWTextLine.h"
#import "GallopUtils.h"


@interface LWTextLayout ()

@property (nonatomic,strong) LWTextContainer* container;
@property (nonatomic,strong) NSAttributedString* text;
@property (nonatomic,assign) CGRect cgPathBox;
@property (nonatomic,assign) CGPathRef cgPath;
@property (nonatomic,assign) CTFrameRef ctFrame;
@property (nonatomic,assign) CTFramesetterRef ctFrameSetter;
@property (nonatomic,assign) CGSize suggestSize;
@property (nonatomic,strong) NSArray<LWTextLine *>* linesArray;
@property (nonatomic,assign) CGRect textBoundingRect;
@property (nonatomic,assign) CGSize textBoundingSize;
@property (nonatomic,strong) NSMutableArray<LWTextAttachment *>* attachments;
@property (nonatomic,strong) NSMutableArray<NSValue *>* attachmentRanges;
@property (nonatomic,strong) NSMutableArray<NSValue *>* attachmentRects;
@property (nonatomic,strong) NSMutableSet<id>* attachmentContentsSet;
@property (nonatomic,strong) NSMutableArray<LWTextHighlight *>* textHighlights;
@property (nonatomic,strong) NSMutableArray<LWTextBackgroundColor *>* backgroundColors;



@end


@implementation LWTextLayout

#pragma mark - Init

+ (LWTextLayout *)lw_layoutWithContainer:(LWTextContainer *)container text:(NSAttributedString *)text {
    if (!text || !container) {
        return nil;
    }
    NSMutableAttributedString* mutableAtrributedText = text.mutableCopy;
    //******* cgPath、cgPathBox *****//
    CGPathRef cgPath = container.path.CGPath;//UIKit坐标系
    CGRect cgPathBox = CGPathGetPathBoundingBox(cgPath);//UIKit坐标系
    //******* ctframeSetter、ctFrame *****//
    CTFramesetterRef ctFrameSetter = CTFramesetterCreateWithAttributedString((CFTypeRef)mutableAtrributedText);
    CGSize suggestSize = CTFramesetterSuggestFrameSizeWithConstraints(ctFrameSetter,CFRangeMake(0,text.length),NULL,CGSizeMake(cgPathBox.size.width, cgPathBox.size.height),NULL);
    cgPathBox = CGRectMake(cgPathBox.origin.x, cgPathBox.origin.y,cgPathBox.size.width,suggestSize.height);
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathAddRect(path, NULL, cgPathBox);
    cgPath = CGPathCreateMutableCopy(path);
    CFRelease(path);
    CTFrameRef ctFrame = CTFramesetterCreateFrame(ctFrameSetter,CFRangeMake(0, mutableAtrributedText.length),cgPath,NULL);
    //******* LWTextLine *****//
    NSInteger rowIndex = -1;
    NSUInteger rowCount = 0;
    CGRect lastRect = CGRectMake(0.0f, - CGFLOAT_MAX, 0.0f, 0.0f);
    CGPoint lastPosition = CGPointMake(0.0f, - CGFLOAT_MAX);
    NSMutableArray* lines = [[NSMutableArray alloc] init];
    CFArrayRef ctLines = CTFrameGetLines(ctFrame);
    CFIndex lineCount = CFArrayGetCount(ctLines);
    CGPoint* lineOrigins = NULL;
    if (lineCount > 0) {
        lineOrigins = malloc(lineCount * sizeof(CGPoint));
        CTFrameGetLineOrigins(ctFrame, CFRangeMake(0, lineCount), lineOrigins);
    }
    //******* textBoundingRect、textBoundingSize ********//
    CGRect textBoundingRect = CGRectZero;
    CGSize textBoundingSize = CGSizeZero;
    NSUInteger lineCurrentIndex = 0;

    NSMutableArray* highlights = [[NSMutableArray alloc] init];
    NSMutableArray* backgroundColors = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < lineCount; i++) {
        CTLineRef ctLine = CFArrayGetValueAtIndex(ctLines, i);
        CFArrayRef ctRuns = CTLineGetGlyphRuns(ctLine);
        CFIndex runCount = CFArrayGetCount(ctRuns);
        if (!ctRuns || runCount == 0){
            continue;
        }
        //****  Highlight(Link)********//
        {
            for (NSUInteger i = 0; i < runCount; i ++) {
                CTRunRef run = CFArrayGetValueAtIndex(ctRuns, i);
                CFIndex glyphCount = CTRunGetGlyphCount(run);
                if (glyphCount == 0) {
                    continue;
                }
                NSDictionary* attributes = (id)CTRunGetAttributes(run);
                LWTextHighlight* highlight = [attributes objectForKey:LWTextLinkAttributedName];
                if (!highlight) {
                    continue;
                }
                NSArray* highlightPositions = [self _highlightPositionsWithCtFrame:ctFrame range:highlight.range];
                highlight.positions = highlightPositions;
                [highlights addObject:highlight];
                break;
            }
        }
        //****  BackgroundColor ********//
        {
            for (NSUInteger i = 0; i < runCount; i ++) {
                CTRunRef run = CFArrayGetValueAtIndex(ctRuns, i);
                CFIndex glyphCount = CTRunGetGlyphCount(run);
                if (glyphCount == 0) {
                    continue;
                }
                NSDictionary* attributes = (id)CTRunGetAttributes(run);
                LWTextBackgroundColor* color = [attributes objectForKey:LWTextBackgroundColorAttributedName];
                if (!color) {
                    continue;
                }
                NSArray* backgroundsPositions = [self _highlightPositionsWithCtFrame:ctFrame range:color.range];
                color.positions = backgroundsPositions;
                [backgroundColors addObject:color];
                break;
            }
        }
        CGPoint ctLineOrigin = lineOrigins[i];//CoreText坐标系
        CGPoint position;//UIKit坐标系
        position.x = cgPathBox.origin.x + ctLineOrigin.x;
        position.y = cgPathBox.size.height + cgPathBox.origin.y - ctLineOrigin.y;
        LWTextLine* line = [LWTextLine lw_textLineWithCTlineRef:ctLine lineOrigin:position];
        [lines addObject:line];
        CGRect rect = line.frame;
        BOOL newRow = YES;
        if (position.x != lastPosition.x) {
            if (rect.size.height > lastRect.size.height) {
                if (rect.origin.y < lastPosition.y && lastPosition.y < rect.origin.y + rect.size.height) {
                    newRow = NO;
                }
            } else {
                if (lastRect.origin.y < position.y && position.y < lastRect.origin.y + lastRect.size.height) {
                    newRow = NO;
                }
            }
        }
        if (newRow){
            rowIndex ++;
        }
        lastRect = rect;
        lastPosition = position;
        line.index = lineCurrentIndex;
        line.row = rowIndex;
        [lines addObject:line];
        rowCount = rowIndex + 1;
        lineCurrentIndex ++;
        if (i == 0){
            textBoundingRect = rect;
        } else {
            textBoundingRect = CGRectUnion(textBoundingRect,rect);
        }
    }
    CFRelease(cgPath);
    cgPathBox = CGRectMake(cgPathBox.origin.x - container.edgeInsets.left,
                           cgPathBox.origin.y - container.edgeInsets.top,
                           cgPathBox.size.width + container.edgeInsets.left + container.edgeInsets.right,
                           cgPathBox.size.height + container.edgeInsets.top + container.edgeInsets.bottom);
    cgPath = [UIBezierPath bezierPathWithRect:cgPathBox].CGPath;
    LWTextLayout* layout = [[self alloc] init];
    layout.container = container;
    layout.text = mutableAtrributedText;
    layout.cgPath = cgPath;
    layout.cgPathBox = cgPathBox;
    layout.ctFrameSetter = ctFrameSetter;
    layout.ctFrame = ctFrame;
    layout.suggestSize = suggestSize;
    layout.linesArray = lines;
    layout.textBoundingRect = textBoundingRect;
    layout.textBoundingSize = textBoundingSize;
    layout.textHighlights = [[NSMutableArray alloc] initWithArray:highlights];
    layout.backgroundColors = [[NSMutableArray alloc] initWithArray:backgroundColors];
    //******* attachments ********//
    layout.attachments = [[NSMutableArray alloc] init];
    layout.attachmentRanges = [[NSMutableArray alloc] init];
    layout.attachmentRects = [[NSMutableArray alloc] init];
    layout.attachmentContentsSet = [[NSMutableSet alloc] init];
    for (NSUInteger i = 0; i < layout.linesArray.count; i ++) {
        LWTextLine* line = lines[i];
        if (line.attachments.count > 0) {
            [layout.attachments addObjectsFromArray:line.attachments];
            [layout.attachmentRanges addObjectsFromArray:line.attachmentRanges];
            [layout.attachmentRects addObjectsFromArray:line.attachmentRects];
            for (LWTextAttachment* attachment in line.attachments) {
                if (attachment.content) {
                    [layout.attachmentContentsSet addObject:attachment.content];
                }
            }
        }
    }
    if (lineOrigins){
        free(lineOrigins);
    }
    return layout;
}

- (void)dealloc {
    if (self.ctFrame) {
        CFRelease(self.ctFrame);
    }
    if (self.ctFrameSetter) {
        CFRelease(self.ctFrameSetter);
    }
}

#pragma mark - Draw & Remove
- (void)drawIncontext:(CGContextRef)context
                 size:(CGSize)size
                point:(CGPoint)point
        containerView:(UIView *)containerView
       containerLayer:(CALayer *)containerLayer {
    [self _drawTextBackgroundColorInContext:context textLayout:self size:size point:point];
    [self _drawTextInContext:context textLayout:self size:size point:point];
    [self _drawAttachmentsIncontext:context textLayou:self size:size point:point containerView:containerView containerLayer:containerLayer];
}

- (void)_drawTextBackgroundColorInContext:(CGContextRef)context  textLayout:(LWTextLayout *)textLayout size:(CGSize)size point:(CGPoint)point {
    for (LWTextBackgroundColor* background in textLayout.backgroundColors) {
        for (NSValue* value in background.positions) {
            CGRect rect = [value CGRectValue];
            CGRect adjustRect = CGRectMake(point.x + rect.origin.x, point.y + rect.origin.y, rect.size.width, rect.size.height);
            UIBezierPath* beizerPath = [UIBezierPath bezierPathWithRoundedRect:adjustRect cornerRadius:2.0f];
            [background.backgroundColor setFill];
            [beizerPath fill];
        }
    }
}

- (void)_drawTextInContext:(CGContextRef) context textLayout:(LWTextLayout *)textLayout size:(CGSize)size point:(CGPoint)point {
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, point.x, point.y);
    CGContextTranslateCTM(context, 0, size.height);
    CGContextScaleCTM(context, 1, -1);
    NSArray* lines = textLayout.linesArray;
    for (NSInteger i = 0; i < lines.count; i ++ ) {
        LWTextLine* line = lines[i];
        CGContextSetTextMatrix(context, CGAffineTransformIdentity);
        CGContextSetTextPosition(context, line.lineOrigin.x ,size.height - line.lineOrigin.y);
        CFArrayRef runs = CTLineGetGlyphRuns(line.CTLine);
        for (NSUInteger j = 0; j < CFArrayGetCount(runs);j ++) {
            CTRunRef run = CFArrayGetValueAtIndex(runs, j);
            CTRunDraw(run, context, CFRangeMake(0, 0));
        }
    }
    CGContextRestoreGState(context);
}

- (void)_drawAttachmentsIncontext:(CGContextRef)context
                        textLayou:(LWTextLayout *)textLayout
                             size:(CGSize)size
                            point:(CGPoint)point
                    containerView:(UIView *)containerView
                   containerLayer:(CALayer *)containerLayer {

    for (NSUInteger i = 0; i < textLayout.attachments.count; i++) {
        LWTextAttachment* attachment = textLayout.attachments[i];
        if (!attachment.content) {
            continue;
        }
        UIImage* image = nil;
        UIView* view = nil;
        CALayer* layer = nil;
        if ([attachment.content isKindOfClass:[UIImage class]]) {
            image = attachment.content;
        } else if ([attachment.content isKindOfClass:[UIView class]]) {
            view = attachment.content;
        } else if ([attachment.content isKindOfClass:[CALayer class]]) {
            layer = attachment.content;
        }
        if ((!image && !view && !layer) || (!image && !view && !layer) ||
            (image && !context) || (view && !containerView)
            || (layer && !containerLayer)) {
            continue;
        }
        CGSize asize = image ? image.size : view ? view.frame.size : layer.frame.size;
        CGRect rect = ((NSValue *)textLayout.attachmentRects[i]).CGRectValue;
        rect = UIEdgeInsetsInsetRect(rect,attachment.contentEdgeInsets);
        rect = LWCGRectFitWithContentMode(rect, asize, attachment.contentMode);
        rect = CGRectPixelRound(rect);
        rect = CGRectStandardize(rect);
        rect.origin.x += point.x;
        rect.origin.y += point.y;
        if (image) {
            CGImageRef ref = image.CGImage;
            if (ref) {
                CGContextSaveGState(context);
                CGContextTranslateCTM(context, 0,CGRectGetMaxY(rect) + CGRectGetMinY(rect));
                CGContextScaleCTM(context, 1, -1);
                CGContextDrawImage(context, rect, ref);
                CGContextRestoreGState(context);
            }
        } else if (view) {
            view.frame = rect;
            [containerView addSubview:view];
        } else if (layer) {
            layer.frame = rect;
            [containerLayer addSublayer:layer];
        }
    }
}


- (void)removeAttachmentFromSuperViewOrLayer {
    
}

#pragma mark - Private
/**
 *  获取LWTextHightlight
 *
 */
+ (NSArray<NSValue *> *)_highlightPositionsWithCtFrame:(CTFrameRef)ctFrame
                                                 range:(NSRange)selectRange {
    CGPathRef path = CTFrameGetPath(ctFrame);
    CGRect boundsRect = CGPathGetBoundingBox(path);
    NSMutableArray* positions = [[NSMutableArray alloc] init];
    NSInteger selectionStartPosition = selectRange.location;
    NSInteger selectionEndPosition = NSMaxRange(selectRange);
    CFArrayRef lines = CTFrameGetLines(ctFrame);
    if (!lines) {
        return nil;
    }
    CFIndex count = CFArrayGetCount(lines);
    CGPoint origins[count];
    CGAffineTransform transform = CGAffineTransformIdentity;
    transform = CGAffineTransformMakeTranslation(0, boundsRect.size.height);
    transform = CGAffineTransformScale(transform, 1.f, -1.f);
    CTFrameGetLineOrigins(ctFrame, CFRangeMake(0,0), origins);
    for (int i = 0; i < count; i++) {
        CGPoint linePoint = origins[i];
        CTLineRef line = CFArrayGetValueAtIndex(lines, i);
        CFRange range = CTLineGetStringRange(line);
        //*** 在同一行 ***//
        if ([self _isPosition:selectionStartPosition inRange:range] && [self _isPosition:selectionEndPosition inRange:range]) {
            CGFloat ascent, descent, leading, offset, offset2;
            offset = CTLineGetOffsetForStringIndex(line, selectionStartPosition, NULL);
            offset2 = CTLineGetOffsetForStringIndex(line, selectionEndPosition, NULL);
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
            CGRect lineRect = CGRectMake(linePoint.x + offset, linePoint.y - descent, offset2 - offset, ascent + descent);
            CGRect rect = CGRectApplyAffineTransform(lineRect, transform);
            CGRect adjustRect = CGRectMake(rect.origin.x + boundsRect.origin.x,
                                           rect.origin.y + boundsRect.origin.y,
                                           rect.size.width,
                                           rect.size.height);
            [positions addObject:[NSValue valueWithCGRect:adjustRect]];
            break;
        }
        //*** 不在在同一行 ***//
        if ([self _isPosition:selectionStartPosition inRange:range]) {
            CGFloat ascent, descent, leading, width, offset;
            offset = CTLineGetOffsetForStringIndex(line, selectionStartPosition, NULL);
            width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
            CGRect lineRect = CGRectMake(linePoint.x + offset, linePoint.y - descent, width - offset, ascent + descent);
            CGRect rect = CGRectApplyAffineTransform(lineRect, transform);
            CGRect adjustRect = CGRectMake(rect.origin.x + boundsRect.origin.x,
                                           rect.origin.y + boundsRect.origin.y,
                                           rect.size.width,
                                           rect.size.height);
            [positions addObject:[NSValue valueWithCGRect:adjustRect]];
        }
        else if (selectionStartPosition < range.location && selectionEndPosition >= range.location + range.length) {
            CGFloat ascent, descent, leading, width;
            width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
            CGRect lineRect = CGRectMake(linePoint.x, linePoint.y - descent, width, ascent + descent);
            CGRect rect = CGRectApplyAffineTransform(lineRect, transform);
            CGRect adjustRect = CGRectMake(rect.origin.x + boundsRect.origin.x,
                                           rect.origin.y + boundsRect.origin.y,
                                           rect.size.width,
                                           rect.size.height);
            [positions addObject:[NSValue valueWithCGRect:adjustRect]];
        }
        else if (selectionStartPosition < range.location && [self _isPosition:selectionEndPosition inRange:range]) {
            CGFloat ascent, descent, leading, width, offset;
            offset = CTLineGetOffsetForStringIndex(line, selectionEndPosition, NULL);
            width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
            CGRect lineRect = CGRectMake(linePoint.x, linePoint.y - descent, offset, ascent + descent);
            CGRect rect = CGRectApplyAffineTransform(lineRect, transform);
            CGRect adjustRect = CGRectMake(rect.origin.x + boundsRect.origin.x,
                                           rect.origin.y + boundsRect.origin.y,
                                           rect.size.width,
                                           rect.size.height);
            [positions addObject:[NSValue valueWithCGRect:adjustRect]];
        }
    }
    return positions;
}

+ (BOOL)_isPosition:(NSInteger)position inRange:(CFRange)range {
    return (position >= range.location && position < range.location + range.length);
}

static inline CGRect CGRectPixelRound(CGRect rect) {
    CGPoint origin = CGPointPixelRound(rect.origin);
    CGPoint corner = CGPointPixelRound(CGPointMake(rect.origin.x + rect.size.width,
                                                   rect.origin.y + rect.size.height));
    return CGRectMake(origin.x, origin.y, corner.x - origin.x, corner.y - origin.y);
}


static inline CGPoint CGPointPixelRound(CGPoint point) {
    CGFloat scale = [UIScreen mainScreen].scale;
    return CGPointMake(round(point.x * scale) / scale,
                       round(point.y * scale) / scale);
}

static CGRect LWCGRectFitWithContentMode(CGRect rect, CGSize size, UIViewContentMode mode) {
    rect = CGRectStandardize(rect);
    size.width = size.width < 0 ? -size.width : size.width;
    size.height = size.height < 0 ? -size.height : size.height;
    CGPoint center = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
    switch (mode) {
        case UIViewContentModeScaleAspectFit:
        case UIViewContentModeScaleAspectFill: {
            if (rect.size.width < 0.01 || rect.size.height < 0.01 ||
                size.width < 0.01 || size.height < 0.01) {
                rect.origin = center;
                rect.size = CGSizeZero;
            } else {
                CGFloat scale;
                if (mode == UIViewContentModeScaleAspectFit) {
                    if (size.width / size.height < rect.size.width / rect.size.height) {
                        scale = rect.size.height / size.height;
                    } else {
                        scale = rect.size.width / size.width;
                    }
                } else {
                    if (size.width / size.height < rect.size.width / rect.size.height) {
                        scale = rect.size.width / size.width;
                    } else {
                        scale = rect.size.height / size.height;
                    }
                }
                size.width *= scale;
                size.height *= scale;
                rect.size = size;
                rect.origin = CGPointMake(center.x - size.width * 0.5, center.y - size.height * 0.5);
            }
        } break;
        case UIViewContentModeCenter: {
            rect.size = size;
            rect.origin = CGPointMake(center.x - size.width * 0.5, center.y - size.height * 0.5);
        } break;
        case UIViewContentModeTop: {
            rect.origin.x = center.x - size.width * 0.5;
            rect.size = size;
        } break;
        case UIViewContentModeBottom: {
            rect.origin.x = center.x - size.width * 0.5;
            rect.origin.y += rect.size.height - size.height;
            rect.size = size;
        } break;
        case UIViewContentModeLeft: {
            rect.origin.y = center.y - size.height * 0.5;
            rect.size = size;
        } break;
        case UIViewContentModeRight: {
            rect.origin.y = center.y - size.height * 0.5;
            rect.origin.x += rect.size.width - size.width;
            rect.size = size;
        } break;
        case UIViewContentModeTopLeft: {
            rect.size = size;
        } break;
        case UIViewContentModeTopRight: {
            rect.origin.x += rect.size.width - size.width;
            rect.size = size;
        } break;
        case UIViewContentModeBottomLeft: {
            rect.origin.y += rect.size.height - size.height;
            rect.size = size;
        } break;
        case UIViewContentModeBottomRight: {
            rect.origin.x += rect.size.width - size.width;
            rect.origin.y += rect.size.height - size.height;
            rect.size = size;
        } break;
        case UIViewContentModeScaleToFill:
        case UIViewContentModeRedraw:
        default: {
            rect = rect;
        }
    }
    return rect;
}

@end
