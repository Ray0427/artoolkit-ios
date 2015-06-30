//
//  AppDelegate.h
//  marker
//
//  Created by iuimini5 on 2015/5/21.
//
//

#import <UIKit/UIKit.h>
@class ARViewController;
@interface AppDelegate : UIResponder <UIApplicationDelegate>{
    UIWindow *window;
    ARViewController *viewController;
}

@property (strong, nonatomic) UIWindow *window;
//@property (nonatomic,retain) IBOutlet ARViewController *viewController;

@end

