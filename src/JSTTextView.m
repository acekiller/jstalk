//
//  JSTTextView.m
//  jstalk
//
//  Created by August Mueller on 1/18/09.
//  Copyright 2009 Flying Meat Inc. All rights reserved.
//

#import "JSTTextView.h"
#import "MarkerLineNumberView.h"
#import "TDParseKit.h"
#import "NoodleLineNumberView.h"
#import "TETextUtils.h"

static NSString *JSTQuotedStringAttributeName = @"JSTQuotedString";

@interface JSTTextView (Private)
- (void)setupLineView;
@end


@implementation JSTTextView

@synthesize keywords=_keywords;
@synthesize lastAutoInsert=_lastAutoInsert;


- (id)initWithFrame:(NSRect)frameRect textContainer:(NSTextContainer *)container {
    
	self = [super initWithFrame:frameRect textContainer:container];
    
	if (self != nil) {
        [self performSelector:@selector(setupLineViewAndStuff) withObject:nil afterDelay:0];
        [self setSmartInsertDeleteEnabled:NO];
    }
    
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    
    self = [super initWithCoder:aDecoder];
	if (self != nil) {
        // what's the right way to do this?
        [self performSelector:@selector(setupLineViewAndStuff) withObject:nil afterDelay:0];
        [self setSmartInsertDeleteEnabled:NO];
    }
    
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [_lineNumberView release];
    [_lastAutoInsert release];
    
    [super dealloc];
}


- (void)setupLineViewAndStuff {
    
    _lineNumberView = [[NoodleLineNumberView alloc] initWithScrollView:[self enclosingScrollView]];
    [[self enclosingScrollView] setVerticalRulerView:_lineNumberView];
    [[self enclosingScrollView] setHasHorizontalRuler:NO];
    [[self enclosingScrollView] setHasVerticalRuler:YES];
    [[self enclosingScrollView] setRulersVisible:YES];
    
    [[self textStorage] setDelegate:self];
    
    /*
     var s = "break case catch continue default delete do else finally for function if in instanceof new return switch this throw try typeof var void while with abstract boolean byte char class const debugger double enum export extends final float goto implements import int interface long native package private protected public short static super synchronized throws transient volatile null true false nil"
     
     words = s.split(" ")
     var i = 0;
     list = ""
     while (i < words.length) {
     list = list + '@"' + words[i] + '", ';
     i++
     }
     
     print("NSArray *blueWords = [NSArray arrayWithObjects:" + list + " nil];")
     */
    
    NSArray *blueWords = [NSArray arrayWithObjects:@"break", @"case", @"catch", @"continue", @"default", @"delete", @"do", @"else", @"finally", @"for", @"function", @"if", @"in", @"instanceof", @"new", @"return", @"switch", @"this", @"throw", @"try", @"typeof", @"var", @"void", @"while", @"with", @"abstract", @"boolean", @"byte", @"char", @"class", @"const", @"debugger", @"double", @"enum", @"export", @"extends", @"final", @"float", @"goto", @"implements", @"import", @"int", @"interface", @"long", @"native", @"package", @"private", @"protected", @"public", @"short", @"static", @"super", @"synchronized", @"throws", @"transient", @"volatile", @"null", @"true", @"false", @"nil",  nil];
    
    NSMutableDictionary *keywords = [NSMutableDictionary dictionary];
    
    for (NSString *word in blueWords) {
        [keywords setObject:[NSColor blueColor] forKey:word];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(textViewDidChangeSelection:) name:NSTextViewDidChangeSelectionNotification object:self];

    
    self.keywords = keywords;
    
    
    [self parseCode:nil];
    
}


- (void)parseCode:(id)sender {
    
    // we should really do substrings...
    
    NSString *sourceString = [[self textStorage] string];
    TDTokenizer *tokenizer = [TDTokenizer tokenizerWithString:sourceString];
    
    tokenizer.commentState.reportsCommentTokens = YES;
    tokenizer.whitespaceState.reportsWhitespaceTokens = YES;
    
    TDToken *eof = [TDToken EOFToken];
    TDToken *tok = nil;
    
    [[self textStorage] beginEditing];
    
    NSUInteger sourceLoc = 0;
    
    while ((tok = [tokenizer nextToken]) != eof) {
        
        NSColor *fontColor = [NSColor blackColor];
        
        if ([tok isQuotedString]) {
            fontColor = [NSColor darkGrayColor];
        }
        else if ([tok isNumber]) {
            fontColor = [NSColor blueColor];
        }
        else if ([tok isComment]) {
            fontColor = [NSColor redColor];
        }
        else if ([tok isWord]) {
            NSColor *c = [_keywords objectForKey:[tok stringValue]];
            fontColor = c ? c : fontColor;
        }
        
        NSUInteger strLen = [[tok stringValue] length];
        
        if (fontColor) {
            [[self textStorage] addAttribute:NSForegroundColorAttributeName value:fontColor range:NSMakeRange(sourceLoc, strLen)];
        }
        
        if ([tok isQuotedString]) {
            [[self textStorage] addAttribute:JSTQuotedStringAttributeName value:[NSNumber numberWithBool:YES] range:NSMakeRange(sourceLoc, strLen)];
        }
        else {
            [[self textStorage] removeAttribute:JSTQuotedStringAttributeName range:NSMakeRange(sourceLoc, strLen)];
        }
        
        sourceLoc += strLen;
    }
    
    
    [[self textStorage] endEditing];
}



- (void) textStorageDidProcessEditing:(NSNotification *)note {
    [self parseCode:nil];
}

- (NSArray *)writablePasteboardTypes {
    return [[super writablePasteboardTypes] arrayByAddingObject:NSRTFPboardType];
}

- (void)insertTab:(id)sender {
    [self insertText:@"    "];
}

- (void)autoInsertText:(NSString*)text {
    
    [super insertText:text];
    [self setLastAutoInsert:text];
    
}

- (void)insertText:(id)insertString {
    
    if (!([JSTPrefs boolForKey:@"codeCompletionEnabled"])) {
        [super insertText:insertString];
        return;
    }
    
    // make sure we're not doing anything fance in a quoted string.
    if (NSMaxRange([self selectedRange]) < [[self textStorage] length] && [[[self textStorage] attributesAtIndex:[self selectedRange].location effectiveRange:nil] objectForKey:JSTQuotedStringAttributeName]) {
        [super insertText:insertString];
        return;
    }
    
    if ([@")" isEqualToString:insertString] && [_lastAutoInsert isEqualToString:@")"]) {
        
        NSRange nextRange   = [self selectedRange];
        nextRange.length = 1;
        
        if (NSMaxRange(nextRange) <= [[self textStorage] length]) {
            
            NSString *next = [[[self textStorage] mutableString] substringWithRange:nextRange];
            
            if ([@")" isEqualToString:next]) {
                // just move our selection over.
                nextRange.length = 0;
                nextRange.location++;
                [self setSelectedRange:nextRange];
                return;
            }
        }
    }
    
    [self setLastAutoInsert:nil];
    
    [super insertText:insertString];
    
    NSRange currentRange = [self selectedRange];
    NSRange r = [self selectionRangeForProposedRange:currentRange granularity:NSSelectByParagraph];
    BOOL atEndOfLine = (NSMaxRange(r) - 1 == NSMaxRange(currentRange));
    
    
    if (atEndOfLine && [@"{" isEqualToString:insertString]) {
        
        r = [self selectionRangeForProposedRange:currentRange granularity:NSSelectByParagraph];
        NSString *myLine = [[[self textStorage] mutableString] substringWithRange:r];
        
        NSMutableString *indent = [NSMutableString string];
        
        int j = 0;
        
        while (j < [myLine length] && ([myLine characterAtIndex:j] == ' ' || [myLine characterAtIndex:j] == '\t')) {
            [indent appendFormat:@"%C", [myLine characterAtIndex:j]];
            j++;
        }
        
        [self autoInsertText:[NSString stringWithFormat:@"\n%@    \n%@}", indent, indent]];
        
        currentRange.location += [indent length] + 5;
        
        [self setSelectedRange:currentRange];
    }
    else if (atEndOfLine && [@"(" isEqualToString:insertString]) {
        
        [self autoInsertText:@")"];
        [self setSelectedRange:currentRange];
        
    }
    else if (atEndOfLine && [@"[" isEqualToString:insertString]) {
        [self autoInsertText:@"]"];
        [self setSelectedRange:currentRange];
    }
    else if ([@"\"" isEqualToString:insertString]) {
        [self autoInsertText:@"\""];
        [self setSelectedRange:currentRange];
    }
}

- (void)insertNewline:(id)sender {
    
    [super insertNewline:sender];
    
    if ([JSTPrefs boolForKey:@"codeCompletionEnabled"]) {
        
        NSRange r = [self selectedRange];
        if (r.location > 0) {
            r.location --;
        }
        
        r = [self selectionRangeForProposedRange:r granularity:NSSelectByParagraph];
        
        NSString *previousLine = [[[self textStorage] mutableString] substringWithRange:r];
        
        int j = 0;
        
        while (j < [previousLine length] && ([previousLine characterAtIndex:j] == ' ' || [previousLine characterAtIndex:j] == '\t')) {
            j++;
        }
        
        if (j > 0) {
            NSString *foo = [[[self textStorage] mutableString] substringWithRange:NSMakeRange(r.location, j)];
            [self insertText:foo];
        }
    }
}


- (BOOL)xrespondsToSelector:(SEL)aSelector {
    
    debug(@"%@: %@?", [self class], NSStringFromSelector(aSelector));
    
    return [super respondsToSelector:aSelector];
    
}

- (void)changeSelectedNumberByDelta:(NSInteger)d {
    NSRange r   = [self selectedRange];
    NSRange wr  = [self selectionRangeForProposedRange:r granularity:NSSelectByWord];
    NSString *s = [[[self textStorage] mutableString] substringWithRange:wr];
    
    NSInteger i = [s integerValue];
    
    if ([s isEqualToString:[NSString stringWithFormat:@"%ld", (long)i]]) {
        
        NSString *newString = [NSString stringWithFormat:@"%ld", (long)(i+d)];
        
        if ([self shouldChangeTextInRange:wr replacementString:newString]) { // auto undo.
            [[self textStorage] replaceCharactersInRange:wr withString:newString];
            [self didChangeText];
            
            r.length = 0;
            [self setSelectedRange:r];    
        }
    }
}

/*
- (void)moveForward:(id)sender {
    debug(@"%s:%d", __FUNCTION__, __LINE__);
    #pragma message "this really really needs to be a pref"
    // defaults write org.jstalk.JSTalkEditor optionNumberIncrement 1
    if ([JSTPrefs boolForKey:@"optionNumberIncrement"]) {
        [self changeSelectedNumberByDelta:-1];
    }
    else {
        [super moveForward:sender];
    }
}

- (void)moveBackward:(id)sender {
    if ([JSTPrefs boolForKey:@"optionNumberIncrement"]) {
        [self changeSelectedNumberByDelta:1];
    }
    else {
        [super moveBackward:sender];
    }
}


- (void)moveToEndOfParagraph:(id)sender {
    
    if (![JSTPrefs boolForKey:@"optionNumberIncrement"] || (([NSEvent modifierFlags] & NSAlternateKeyMask) != 0)) {
        [super moveToEndOfParagraph:sender];
    }
}

- (void)moveToBeginningOfParagraph:(id)sender {
    if (![JSTPrefs boolForKey:@"optionNumberIncrement"] || (([NSEvent modifierFlags] & NSAlternateKeyMask) != 0)) {
        [super moveToBeginningOfParagraph:sender];
    }
}
*/
/*
- (void)moveDown:(id)sender {
    debug(@"%s:%d", __FUNCTION__, __LINE__);
}

- (void)moveDownAndModifySelection:(id)sender {
    debug(@"%s:%d", __FUNCTION__, __LINE__);
}
*/
// Mimic BBEdit's option-delete behavior, which is THE WAY IT SHOULD BE DONE

- (void)deleteWordForward:(id)sender {
    
    NSRange r = [self selectedRange];
    NSUInteger textLength = [[self textStorage] length];
    
    if (r.length || (NSMaxRange(r) >= textLength)) {
        [super deleteWordForward:sender];
        return;
    }
    
    // delete the whitespace forward.
    
    NSRange paraRange = [self selectionRangeForProposedRange:r granularity:NSSelectByParagraph];
    
    NSUInteger diff = r.location - paraRange.location;
    
    paraRange.location += diff;
    paraRange.length   -= diff;
    
    NSString *foo = [[[self textStorage] string] substringWithRange:paraRange];
    
    NSUInteger len = 0;
    while ([foo characterAtIndex:len] == ' ' && len < paraRange.length) {
        len++;
    }
    
    if (!len) {
        [super deleteWordForward:sender];
        return;
    }
    
    r.length = len;
    
    if ([self shouldChangeTextInRange:r replacementString:@""]) { // auto undo.
        [self replaceCharactersInRange:r withString:@""];
    }
}

- (void)deleteBackward:(id)sender {
    if ([[self delegate] respondsToSelector:@selector(textView:doCommandBySelector:)]) {
        // If the delegate wants a crack at command selectors, give it a crack at the standard selector too.
        if ([[self delegate] textView:self doCommandBySelector:@selector(deleteBackward:)]) {
            return;
        }
    }
    else {
        NSRange charRange = [self rangeForUserTextChange];
        if (charRange.location != NSNotFound) {
            if (charRange.length > 0) {
                // Non-zero selection.  Delete normally.
                [super deleteBackward:sender];
            } else {
                if (charRange.location == 0) {
                    // At beginning of text.  Delete normally.
                    [super deleteBackward:sender];
                } else {
                    NSString *string = [self string];
                    NSRange paraRange = [string lineRangeForRange:NSMakeRange(charRange.location - 1, 1)];
                    if (paraRange.location == charRange.location) {
                        // At beginning of line.  Delete normally.
                        [super deleteBackward:sender];
                    } else {
                        unsigned tabWidth = 4; //[[TEPreferencesController sharedPreferencesController] tabWidth];
                        unsigned indentWidth = 4;// [[TEPreferencesController sharedPreferencesController] indentWidth];
                        BOOL usesTabs = NO; //[[TEPreferencesController sharedPreferencesController] usesTabs];
                        NSRange leadingSpaceRange = paraRange;
                        unsigned leadingSpaces = TE_numberOfLeadingSpacesFromRangeInString(string, &leadingSpaceRange, tabWidth);
                        
                        if (charRange.location > NSMaxRange(leadingSpaceRange)) {
                            // Not in leading whitespace.  Delete normally.
                            [super deleteBackward:sender];
                        } else {
                            NSTextStorage *text = [self textStorage];
                            unsigned leadingIndents = leadingSpaces / indentWidth;
                            NSString *replaceString;
                            
                            // If we were indented to an fractional level just go back to the last even multiple of indentWidth, if we were exactly on, go back a full level.
                            if (leadingSpaces % indentWidth == 0) {
                                leadingIndents--;
                            }
                            leadingSpaces = leadingIndents * indentWidth;
                            replaceString = ((leadingSpaces > 0) ? TE_tabbifiedStringWithNumberOfSpaces(leadingSpaces, tabWidth, usesTabs) : @"");
                            if ([self shouldChangeTextInRange:leadingSpaceRange replacementString:replaceString]) {
                                NSDictionary *newTypingAttributes;
                                if (charRange.location < [string length]) {
                                    newTypingAttributes = [[text attributesAtIndex:charRange.location effectiveRange:NULL] retain];
                                } else {
                                    newTypingAttributes = [[text attributesAtIndex:(charRange.location - 1) effectiveRange:NULL] retain];
                                }
                                
                                [text replaceCharactersInRange:leadingSpaceRange withString:replaceString];
                                
                                [self setTypingAttributes:newTypingAttributes];
                                [newTypingAttributes release];
                                
                                [self didChangeText];
                            }
                        }
                    }
                }
            }
        }
    }
}



- (void)TE_doUserIndentByNumberOfLevels:(int)levels {
    // Because of the way paragraph ranges work we will add spaces a final paragraph separator only if the selection is an insertion point at the end of the text.
    // We ask for rangeForUserTextChange and extend it to paragraph boundaries instead of asking rangeForUserParagraphAttributeChange because this is not an attribute change and we don't want it to be affected by the usesRuler setting.
    NSRange charRange = [[self string] lineRangeForRange:[self rangeForUserTextChange]];
    NSRange selRange = [self selectedRange];
    if (charRange.location != NSNotFound) {
        NSTextStorage *textStorage = [self textStorage];
        NSAttributedString *newText;
        unsigned tabWidth = 4;
        unsigned indentWidth = 4;
        BOOL usesTabs = NO;
        
        selRange.location -= charRange.location;
        newText = TE_attributedStringByIndentingParagraphs([textStorage attributedSubstringFromRange:charRange], levels,  &selRange, [self typingAttributes], tabWidth, indentWidth, usesTabs);
        
        selRange.location += charRange.location;
        if ([self shouldChangeTextInRange:charRange replacementString:[newText string]]) {
            [[textStorage mutableString] replaceCharactersInRange:charRange withString:[newText string]];
            //[textStorage replaceCharactersInRange:charRange withAttributedString:newText];
            [self setSelectedRange:selRange];
            [self didChangeText];
        }
    }
}


- (void)shiftLeft:(id)sender {
    [self TE_doUserIndentByNumberOfLevels:-1];
}

- (void)shiftRight:(id)sender {
    [self TE_doUserIndentByNumberOfLevels:1];
}

- (void)textViewDidChangeSelection:(NSNotification *)notification {
    NSTextView *textView = [notification object];
    NSRange selRange = [textView selectedRange];
    //TEPreferencesController *prefs = [TEPreferencesController sharedPreferencesController];
    
    //if ([prefs selectToMatchingBrace]) {
    if (YES) {
        // The NSTextViewDidChangeSelectionNotification is sent before the selection granularity is set.  Therefore we can't tell a double-click by examining the granularity.  Fortunately there's another way.  The mouse-up event that ended the selection is still the current event for the app.  We'll check that instead.  Perhaps, in an ideal world, after checking the length we'd do this instead: ([textView selectionGranularity] == NSSelectByWord).
        if ((selRange.length == 1) && ([[NSApp currentEvent] type] == NSLeftMouseUp) && ([[NSApp currentEvent] clickCount] == 2)) {
            NSRange matchRange = TE_findMatchingBraceForRangeInString(selRange, [textView string]);
            
            if (matchRange.location != NSNotFound) {
                selRange = NSUnionRange(selRange, matchRange);
                [textView setSelectedRange:selRange];
                [textView scrollRangeToVisible:matchRange];
            }
        }
    }
    
    //if ([prefs showMatchingBrace]) {
    if (YES) {
        NSRange oldSelRangePtr;
        
        [[[notification userInfo] objectForKey:@"NSOldSelectedCharacterRange"] getValue:&oldSelRangePtr];
        
        // This test will catch typing sel changes, also it will catch right arrow sel changes, which I guess we can live with.  MF:??? Maybe we should catch left arrow changes too for consistency...
        if ((selRange.length == 0) && (selRange.location > 0) && ([[NSApp currentEvent] type] == NSKeyDown) && (oldSelRangePtr.location == selRange.location - 1)) {
            NSRange origRange = NSMakeRange(selRange.location - 1, 1);
            unichar origChar = [[textView string] characterAtIndex:origRange.location];
            
            if (TE_isClosingBrace(origChar)) {
                NSRange matchRange = TE_findMatchingBraceForRangeInString(origRange, [textView string]);
                if (matchRange.location != NSNotFound) {
                    
                    // do this with a delay, since for some reason it only works when we use the arrow keys otherwise.
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self showFindIndicatorForRange:matchRange];
                        });
                    });
                }
            }
        }
    }
}



- (NSRange)selectionRangeForProposedRange:(NSRange)proposedSelRange granularity:(NSSelectionGranularity)granularity {
    
    // check for cases where we've got: [foo setValue:bar forKey:"x"]; and we double click on setValue.  The default way NSTextView does the selection
    // is to have it highlight all of setValue:bar, which isn't what we want.  So.. we mix it up a bit.
    // There's probably a better way to do this, but I don't currently know what it is.
    
    if (granularity == NSSelectByWord && ([[NSApp currentEvent] type] == NSLeftMouseUp || [[NSApp currentEvent] type] == NSLeftMouseDown) && [[NSApp currentEvent] clickCount] > 1) {
        
        NSRange r           = [super selectionRangeForProposedRange:proposedSelRange granularity:granularity];
        NSString *s         = [[[self textStorage] mutableString] substringWithRange:r];
        NSRange colLocation = [s rangeOfString:@":"];
        
        if (colLocation.location != NSNotFound) {
            
            if (proposedSelRange.location > (r.location + colLocation.location)) {
                r.location = r.location + colLocation.location + 1;
                r.length = [s length] - colLocation.location - 1;
            }
            else {
                r.length = colLocation.location;
            }
        }
        
        return r;
    }
    
    return [super selectionRangeForProposedRange:proposedSelRange granularity:granularity];
}

- (void)setInsertionPointFromDragOpertion:(id <NSDraggingInfo>)sender {
    
    NSLayoutManager *layoutManager = [self layoutManager];
    NSTextContainer *textContainer = [self textContainer];
    
    NSUInteger glyphIndex, charIndex, length = [[self textStorage] length];
    NSPoint point = [self convertPoint:[sender draggingLocation] fromView:nil];
    
    // Convert those coordinates to the nearest glyph index
    glyphIndex = [layoutManager glyphIndexForPoint:point inTextContainer:textContainer];
    
    // Convert the glyph index to a character index
    charIndex = [layoutManager characterIndexForGlyphAtIndex:glyphIndex];
    
    // put the selection where we have the mouse.
    if (charIndex == (length - 1)) {
        [self setSelectedRange:NSMakeRange(charIndex+1, 0)];
        //[self setSelectedRange:NSMakeRange(charIndex, 0)];
    }
    else {
        [self setSelectedRange:NSMakeRange(charIndex, 0)];
    }
    
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
    
    if (([NSEvent modifierFlags] & NSAlternateKeyMask) != 0) {
        
        [self setInsertionPointFromDragOpertion:sender];
        
        NSPasteboard *paste = [sender draggingPasteboard];
        NSArray *fileArray = [paste propertyListForType:NSFilenamesPboardType];
        
        for (NSString *path in fileArray) {
            
            [self insertText:[NSString stringWithFormat:@"[NSURL fileURLWithPath:\"%@\"]", path]];
            
            if ([fileArray count] > 1) {
                [self insertNewline:nil];
            }
        }
        
        return YES;
    }
    
    return [super performDragOperation:sender];
}


@end

// stolen from NSTextStorage_TETextExtras.m
@implementation NSTextStorage (TETextExtras)

- (BOOL)_usesProgrammingLanguageBreaks {
    return YES;
}
@end
