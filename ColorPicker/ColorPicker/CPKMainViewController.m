#import "CPKMainViewController.h"
#import "CPKColorNamer.h"
#import "CPKControlsView.h"
#import "CPKEyedropperWindow.h"
#import "CPKFavorite.h"
#import "CPKFavoritesView.h"
#import "CPKFlippedView.h"
#import "CPKRGBView.h"
#import "NSColor+CPK.h"

const CGFloat kDesiredWidth = 220;
const CGFloat kFavoritesHeight = 100;

static const CGFloat kLeftMargin = 8;
static const CGFloat kRightMargin = 8;
static const CGFloat kBottomMargin = 8;

@interface CPKMainViewController ()
@property(nonatomic, copy) void (^block)(NSColor *);
@property(nonatomic) NSColor *selectedColor;
@property(nonatomic) CGFloat desiredHeight;
@property(nonatomic) CPKRGBView *rgbView;
@property(nonatomic) CPKControlsView *controlsView;
@property(nonatomic) CPKFavoritesView *favoritesView;
@property(nonatomic) NSColorPanel *colorPanel;
@property(nonatomic) BOOL alphaAllowed;
@end

@implementation CPKMainViewController

- (instancetype)initWithBlock:(void (^)(NSColor *))block
                        color:(NSColor *)color
                 alphaAllowed:(BOOL)alphaAllowed {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _block = [block copy];
        if (!color) {
            color = [NSColor cpk_colorWithRed:0 green:0 blue:0 alpha:0];
        }
        if (!alphaAllowed) {
            color = [color colorWithAlphaComponent:1];
        }
        color = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        _selectedColor = color;
        self.alphaAllowed = alphaAllowed;
    }
    return self;
}

- (void)loadView {
    // The 100 value below is temporary and will be changed before we return to the correct height.
    self.view = [[CPKFlippedView alloc] initWithFrame:NSMakeRect(0,
                                                                 0,
                                                                 kDesiredWidth,
                                                                 100)];
    self.view.autoresizesSubviews = NO;

    __weak __typeof(self) weakSelf = self;
    self.rgbView = [[CPKRGBView alloc] initWithFrame:self.view.bounds
                                               block: ^(NSColor *color) {
                                                   [weakSelf selectColor:color];
                                               }
                                               color:_selectedColor
                                        alphaAllowed:self.alphaAllowed];
    [self.rgbView sizeToFit];

    self.controlsView =
        [[CPKControlsView alloc] initWithFrame:NSMakeRect(0,
                                                          NSMaxY(self.rgbView.frame),
                                                          kDesiredWidth,
                                                          [CPKControlsView desiredHeight])];
    self.controlsView.swatchColor = _selectedColor;
    self.controlsView.addFavoriteBlock = ^() {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Name this color";
        alert.informativeText = @"Enter a name for this new saved color:";
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:@"Cancel"];

        NSTextField *input =
            [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
        input.stringValue = [[CPKColorNamer sharedInstance] nameForColor:weakSelf.selectedColor];
        alert.accessoryView = input;
        [alert layout];
        [[alert window] makeFirstResponder:input];
        NSInteger button = [alert runModal];
        if (button == NSAlertFirstButtonReturn) {
            [weakSelf.favoritesView addFavorite:[CPKFavorite favoriteWithColor:weakSelf.selectedColor
                                                                          name:input.stringValue]];
        }
    };
    self.controlsView.removeFavoriteBlock = ^() {
        [weakSelf.favoritesView removeSelectedFavorites];
    };
    self.controlsView.startPickingBlock = ^() {
        NSColor *color = [CPKEyedropperWindow pickColor];
        if (color) {
            weakSelf.rgbView.selectedColor = color;
        }
    };
    self.controlsView.toggleNativePickerBlock = ^(BOOL open) {
        if (open) {
            weakSelf.colorPanel = [NSColorPanel sharedColorPanel];
            weakSelf.colorPanel.showsAlpha = weakSelf.alphaAllowed;
            weakSelf.colorPanel.color = weakSelf.selectedColor;
            [weakSelf.colorPanel setTarget:weakSelf];
            [weakSelf.colorPanel setAction:@selector(colorPanelColorDidChange:)];
            [weakSelf.colorPanel orderFront:nil];
            NSRect frame = weakSelf.colorPanel.frame;
            frame.origin = self.view.window.frame.origin;
            [weakSelf.colorPanel setFrame:frame display:YES];
        } else {
            weakSelf.colorPanel = [NSColorPanel sharedColorPanel];
            weakSelf.colorPanel.target = nil;
            [weakSelf.colorPanel orderOut:nil];
            weakSelf.colorPanel = nil;
        }
    };
    self.favoritesView =
        [[CPKFavoritesView alloc] initWithFrame:NSMakeRect(kLeftMargin,
                                                           NSMaxY(self.controlsView.frame),
                                                           kDesiredWidth - kLeftMargin - kRightMargin,
                                                           [self favoritesViewHeight])];
    self.favoritesView.selectionDidChangeBlock = ^(NSColor *newColor) {
        if (newColor) {
            weakSelf.rgbView.selectedColor = newColor;
            weakSelf.controlsView.removeEnabled = YES;
        } else {
            weakSelf.controlsView.removeEnabled = NO;
        }
    };

    self.desiredHeight = NSMaxY(self.favoritesView.frame) + kBottomMargin;

    self.view.subviews = @[ self.rgbView,
                            self.controlsView,
                            self.favoritesView ];

    self.view.frame = NSMakeRect(0, 0, kDesiredWidth, self.desiredHeight);
}

- (NSSize)desiredSize {
    [self view];
    return NSMakeSize(kDesiredWidth, self.desiredHeight);
}

- (CGFloat)favoritesViewHeight {
    return kFavoritesHeight;
}

- (void)viewWillDisappear {
    __weak NSColorPanel *colorPanel = self.colorPanel;
    dispatch_async(dispatch_get_main_queue(), ^{
        [colorPanel setTarget:nil];
        [colorPanel orderOut:nil];
    });
    self.colorPanel = nil;
}

- (void)colorPanelColorDidChange:(id)sender {
    NSColorPanel *colorPanel = [NSColorPanel sharedColorPanel];
    self.rgbView.selectedColor = [colorPanel color];
}

- (void)setColorPanel:(NSColorPanel *)colorPanel {
    if (colorPanel) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(colorPanelDidClose:)
                                                     name:NSWindowWillCloseNotification
                                                   object:_colorPanel];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSWindowWillCloseNotification
                                                      object:_colorPanel];
    }
    _colorPanel = colorPanel;
}

- (void)colorPanelDidClose:(NSNotification *)notification {
    [self.controlsView colorPanelDidClose];
    self.colorPanel = nil;
}

- (void)selectColor:(NSColor *)color {
    self.selectedColor = color;
    self.controlsView.swatchColor = color;
    _block(color);
    [self.favoritesView selectColor:color];
}

@end
