//
//  ViewController.h
//  marker
//
//  Created by iuimini5 on 2015/5/21.
//
//

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <AR/ar.h>
#include <AR/video.h>
#include <AR/gsub_es.h>
#include <AR/sys/CameraVideo.h>
#import "EAGLView.h"
@class ARView;
@interface ViewController : UIViewController <CameraVideoTookPictureDelegate>

- (void) processFrame:(AR2VideoBufferT *)buffer;
@property (readonly) ARView *glView;
@property (readonly) ARGL_CONTEXT_SETTINGS_REF arglContextSettings;

@property (readonly, nonatomic, getter=isRunning) BOOL running;
@property (nonatomic, getter=isPaused) BOOL paused;
@property (nonatomic) NSInteger runLoopInterval;
@end

