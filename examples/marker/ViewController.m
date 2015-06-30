//
//  ViewController.m
//  marker
//
//  Created by iuimini5 on 2015/5/21.
//
//

#import "ViewController.h"
#import <AR/gsub_es.h>
#import "ARView.h"
@interface ViewController ()

@end

#define VIEW_SCALEFACTOR        1.0f
#define VIEW_DISTANCE_MIN        5.0f          // Objects closer to the camera than this will not be displayed.
#define VIEW_DISTANCE_MAX        2000.0f        // Objects further away from the camera than this will not be displayed.

@implementation ViewController{
    
    BOOL            running;
    NSInteger       runLoopInterval;
    NSTimeInterval  runLoopTimePrevious;
    BOOL            videoPaused;
    
    // Video acquisition
    AR2VideoParamT *gVid;
    
    // Marker detection.
    ARHandle       *gARHandle;
    ARPattHandle   *gARPattHandle;
    long            gCallCountMarkerDetect;
    // Transformation matrix retrieval.
    AR3DHandle     *gAR3DHandle;
    ARdouble        gPatt_width;            // Per-marker, but we are using only 1 marker.
    ARdouble        gPatt_trans[3][4];      // Per-marker, but we are using only 1 marker.
    int             gPatt_found;            // Per-marker, but we are using only 1 marker.
    int             gPatt_id;               // Per-marker, but we are using only 1 marker.
    BOOL            useContPoseEstimation;
    
    // Drawing.
    ARParamLT      *gCparamLT;
    ARView         *glView;
    ARGL_CONTEXT_SETTINGS_REF arglContextSettings;
}
@synthesize glView;
@synthesize arglContextSettings;
@synthesize running, runLoopInterval;

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    // Init instance variables.
//    glView = nil;
    gVid = NULL;
//    gCparamLT = NULL;
    gARHandle = NULL;
    gARPattHandle = NULL;
    gCallCountMarkerDetect = 0;
    gAR3DHandle = NULL;
    useContPoseEstimation = FALSE;
//    arglContextSettings = NULL;
    running = FALSE;
    videoPaused = FALSE;
    runLoopTimePrevious = CFAbsoluteTimeGetCurrent();
}
- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self start];
}
- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}
- (void)startRunLoop
{
    if (!running) {
        // After starting the video, new frames will invoke cameraVideoTookPicture:userData:.
        if (ar2VideoCapStart(gVid) != 0) {
            NSLog(@"Error: Unable to begin camera data capture.\n");
            [self stop];
            return;
        }
        running = TRUE;
    }
}
- (void)stopRunLoop
{
    if (running) {
        ar2VideoCapStop(gVid);
        running = FALSE;
    }
}

static void startCallback(void *userData);

- (IBAction)start
{
    // Open the video path.
    char *vconf = ""; // See http://www.artoolworks.com/support/library/Configuring_video_capture_in_ARToolKit_Professional#AR_VIDEO_DEVICE_IPHONE
    if (!(gVid = ar2VideoOpenAsync(vconf, startCallback, (__bridge void *)(self)))) {
        NSLog(@"Error: Unable to open connection to camera.\n");
        [self stop];
        return;
    }
}
static void startCallback(void *userData)
{
    ViewController *vc = (__bridge ViewController *)userData;
    
    [vc start2];
}
- (void) start2
{
    // Find the size of the window.
    int xsize, ysize;
    if (ar2VideoGetSize(gVid, &xsize, &ysize) < 0) {
        NSLog(@"Error: ar2VideoGetSize.\n");
        [self stop];
        return;
    }
    
    // Get the format in which the camera is returning pixels.
    AR_PIXEL_FORMAT pixFormat = ar2VideoGetPixelFormat(gVid);
    if (pixFormat == AR_PIXEL_FORMAT_INVALID) {
        NSLog(@"Error: Camera is using unsupported pixel format.\n");
        [self stop];
        return;
    }
    
    // Work out if the front camera is being used. If it is, flip the viewing frustum for
    // 3D drawing.
    BOOL flipV = FALSE;
    int frontCamera;
    if (ar2VideoGetParami(gVid, AR_VIDEO_PARAM_IOS_CAMERA_POSITION, &frontCamera) >= 0) {
        if (frontCamera == AR_VIDEO_IOS_CAMERA_POSITION_FRONT) flipV = TRUE;
    }
    
    // Tell arVideo what the typical focal distance will be. Note that this does NOT
    // change the actual focus, but on devices with non-fixed focus, it lets arVideo
    // choose a better set of camera parameters.
    ar2VideoSetParami(gVid, AR_VIDEO_PARAM_IOS_FOCUS, AR_VIDEO_IOS_FOCUS_0_3M); // Default is 0.3 metres. See <AR/sys/videoiPhone.h> for allowable values.
    
    // Load the camera parameters, resize for the window and init.
    ARParam cparam;
    if (ar2VideoGetCParam(gVid, &cparam) < 0) {
        char cparam_name[] = "Data2/camera_para.dat";
        NSLog(@"Unable to automatically determine camera parameters. Using default.\n");
        if (arParamLoad(cparam_name, 1, &cparam) < 0) {
            NSLog(@"Error: Unable to load parameter file %s for camera.\n", cparam_name);
            [self stop];
            return;
        }
    }
    if (cparam.xsize != xsize || cparam.ysize != ysize) {
#ifdef DEBUG
        fprintf(stdout, "*** Camera Parameter resized from %d, %d. ***\n", cparam.xsize, cparam.ysize);
#endif
        arParamChangeSize(&cparam, xsize, ysize, &cparam);
    }
#ifdef DEBUG
    fprintf(stdout, "*** Camera Parameter ***\n");
    arParamDisp(&cparam);
#endif
    if ((gCparamLT = arParamLTCreate(&cparam, AR_PARAM_LT_DEFAULT_OFFSET)) == NULL) {
        NSLog(@"Error: arParamLTCreate.\n");
        [self stop];
        return;
    }
    
    // AR init.
    if ((gARHandle = arCreateHandle(gCparamLT)) == NULL) {
        NSLog(@"Error: arCreateHandle.\n");
        [self stop];
        return;
    }
    if (arSetPixelFormat(gARHandle, pixFormat) < 0) {
        NSLog(@"Error: arSetPixelFormat.\n");
        [self stop];
        return;
    }
    if ((gAR3DHandle = ar3DCreateHandle(&gCparamLT->param)) == NULL) {
        NSLog(@"Error: ar3DCreateHandle.\n");
        [self stop];
        return;
    }
    
    // libARvideo on iPhone uses an underlying class called CameraVideo. Here, we
    // access the instance of this class to get/set some special types of information.
    CameraVideo *cameraVideo = ar2VideoGetNativeVideoInstanceiPhone(gVid->device.iPhone);
    if (!cameraVideo) {
        NSLog(@"Error: Unable to set up AR camera: missing CameraVideo instance.\n");
        [self stop];
        return;
    }
    
    // The camera will be started by -startRunLoop.
    [cameraVideo setTookPictureDelegate:self];
    [cameraVideo setTookPictureDelegateUserData:NULL];
    
    // Other ARToolKit setup.
    arSetMarkerExtractionMode(gARHandle, AR_USE_TRACKING_HISTORY_V2);
    //arSetMarkerExtractionMode(gARHandle, AR_NOUSE_TRACKING_HISTORY);
    //arSetLabelingThreshMode(gARHandle, AR_LABELING_THRESH_MODE_MANUAL); // Uncomment to use  manual thresholding.
    
    // Allocate the OpenGL view.
    glView = [[ARView alloc] initWithFrame:[[UIScreen mainScreen] bounds] pixelFormat:kEAGLColorFormatRGBA8 depthFormat:kEAGLDepth16 withStencil:NO preserveBackbuffer:NO]; // Don't retain it, as it will be retained when by self.view.
    glView.arViewController = self;
    self.view = glView;
    
    // Create the OpenGL projection from the calibrated camera parameters.
    // If flipV is set, flip.
    GLfloat frustum[16];
    arglCameraFrustumRHf(&gCparamLT->param, VIEW_DISTANCE_MIN, VIEW_DISTANCE_MAX, frustum);
    [glView setCameraLens:frustum];
    glView.contentFlipV = flipV;
    
    // Set up content positioning.
    glView.contentMode = UIViewContentModeScaleAspectFill;
    glView.contentWidth = gARHandle->xsize;
    glView.contentHeight = gARHandle->ysize;
    BOOL isBackingTallerThanWide = (glView.surfaceSize.height > glView.surfaceSize.width);
    if (glView.contentWidth > glView.contentHeight) glView.contentRotate90 = isBackingTallerThanWide;
    else glView.contentRotate90 = !isBackingTallerThanWide;
#ifdef DEBUG
    NSLog(@"[ARViewController start] content %dx%d (wxh) will display in GL context %dx%d%s.\n", glView.contentWidth, glView.contentHeight, (int)glView.surfaceSize.width, (int)glView.surfaceSize.height, (glView.contentRotate90 ? " rotated" : ""));
#endif
    
    // Setup ARGL to draw the background video.
    arglContextSettings = arglSetupForCurrentContext(&gCparamLT->param, pixFormat);
    
    arglSetRotate90(arglContextSettings, (glView.contentWidth > glView.contentHeight ? isBackingTallerThanWide : !isBackingTallerThanWide));
    if (flipV) arglSetFlipV(arglContextSettings, TRUE);
    int width, height;
    ar2VideoGetBufferSize(gVid, &width, &height);
    arglPixelBufferSizeSet(arglContextSettings, width, height);
    
    // Prepare ARToolKit to load patterns.
    if (!(gARPattHandle = arPattCreateHandle())) {
        NSLog(@"Error: arPattCreateHandle.\n");
        [self stop];
        return;
    }
    arPattAttach(gARHandle, gARPattHandle);
    
    // Load marker(s).
    // Loading only 1 pattern in this example.
    char *patt_name  = "Data2/patt.hiro";
    if ((gPatt_id = arPattLoad(gARPattHandle, patt_name)) < 0) {
        NSLog(@"Error loading pattern file %s.\n", patt_name);
        [self stop];
        return;
    }
    gPatt_width = 40.0f;
    gPatt_found = FALSE;
    
    // For FPS statistics.
    arUtilTimerReset();
    gCallCountMarkerDetect = 0;
    
    //Create our runloop timer
    [self setRunLoopInterval:2]; // Target 30 fps on a 60 fps device.
    [self startRunLoop];
}

- (IBAction)stop
{
    [self stopRunLoop];
    
    if (arglContextSettings) {
        arglCleanup(arglContextSettings);
        arglContextSettings = NULL;
    }
    self.view = nil; // Will result in glView being released.
    
    if (gARHandle) arPattDetach(gARHandle);
    if (gARPattHandle) {
        arPattDeleteHandle(gARPattHandle);
        gARPattHandle = NULL;
    }
    if (gAR3DHandle) ar3DDeleteHandle(&gAR3DHandle);
    if (gARHandle) {
        arDeleteHandle(gARHandle);
        gARHandle = NULL;
    }
    arParamLTFree(&gCparamLT);
    if (gVid) {
        ar2VideoClose(gVid);
        gVid = NULL;
    }
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
- (void) processFrame:(AR2VideoBufferT *)buffer
{
    ARdouble err;
    int j, k;
    
    if (buffer) {
        
        // Upload the frame to OpenGL.
//        if (buffer->bufPlaneCount == 2) arglPixelBufferDataUploadBiPlanar(arglContextSettings, buffer->bufPlanes[0], buffer->bufPlanes[1]);
//        else arglPixelBufferDataUpload(arglContextSettings, buffer->buff);
        
        gCallCountMarkerDetect++; // Increment ARToolKit FPS counter.
#ifdef DEBUG
        NSLog(@"video frame %ld.\n", gCallCountMarkerDetect);
#endif
//#ifdef DEBUG
//        if (gCallCountMarkerDetect % 150 == 0) {
//            NSLog(@"*** Camera - %f (frame/sec)\n", (double)gCallCountMarkerDetect/arUtilTimer());
//            gCallCountMarkerDetect = 0;
//            arUtilTimerReset();
//        }
//#endif
        
        // Detect the markers in the video frame.
        if (arDetectMarker(gARHandle, buffer->buff) < 0) return;
#ifdef DEBUG
        NSLog(@"found %d marker(s).\n", gARHandle->marker_num);
#endif
        
        // Check through the marker_info array for highest confidence
        // visible marker matching our preferred pattern.
        k = -1;
        for (j = 0; j < gARHandle->marker_num; j++) {
            if (gARHandle->markerInfo[j].id == gPatt_id) {
                if (k == -1) k = j; // First marker detected.
                else if (gARHandle->markerInfo[j].cf > gARHandle->markerInfo[k].cf) k = j; // Higher confidence marker detected.
            }
        }
        
        if (k != -1) {
#ifdef DEBUG
            NSLog(@"marker %d matched pattern %d.\n", k, gPatt_id);
#endif
            // Get the transformation between the marker and the real camera into gPatt_trans.
            if (gPatt_found && useContPoseEstimation) {
                err = arGetTransMatSquareCont(gAR3DHandle, &(gARHandle->markerInfo[k]), gPatt_trans, gPatt_width, gPatt_trans);
            } else {
                err = arGetTransMatSquare(gAR3DHandle, &(gARHandle->markerInfo[k]), gPatt_width, gPatt_trans);
            }
            float modelview[16]; // We have a new pose, so set that.
#ifdef ARDOUBLE_IS_FLOAT
            arglCameraViewRHf(gPatt_trans, modelview, VIEW_SCALEFACTOR);
#else
            float patt_transf[3][4];
            int r, c;
            for (r = 0; r < 3; r++) {
                for (c = 0; c < 4; c++) {
                    patt_transf[r][c] = (float)(gPatt_trans[r][c]);
                }
            }
            arglCameraViewRHf(patt_transf, modelview, VIEW_SCALEFACTOR);
#endif
//            gPatt_found = TRUE;
//            [glView setCameraPose:modelview];
//        } else {
//            gPatt_found = FALSE;
//            [glView setCameraPose:NULL];
        }
        
        // Get current time (units = seconds).
        NSTimeInterval runLoopTimeNow;
        runLoopTimeNow = CFAbsoluteTimeGetCurrent();
//        [glView updateWithTimeDelta:(runLoopTimeNow - runLoopTimePrevious)];
//        
//        // The display has changed.
//        [glView drawView:self];
        
        // Save timestamp for next loop.
        runLoopTimePrevious = runLoopTimeNow;
    }
}

@end
