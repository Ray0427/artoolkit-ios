//
//  ARViewController.m
//  ARAppES1
//
//  Disclaimer: IMPORTANT:  This Daqri software is supplied to you by Daqri
//  LLC ("Daqri") in consideration of your agreement to the following
//  terms, and your use, installation, modification or redistribution of
//  this Daqri software constitutes acceptance of these terms.  If you do
//  not agree with these terms, please do not use, install, modify or
//  redistribute this Daqri software.
//
//  In consideration of your agreement to abide by the following terms, and
//  subject to these terms, Daqri grants you a personal, non-exclusive
//  license, under Daqri's copyrights in this original Daqri software (the
//  "Daqri Software"), to use, reproduce, modify and redistribute the Daqri
//  Software, with or without modifications, in source and/or binary forms;
//  provided that if you redistribute the Daqri Software in its entirety and
//  without modifications, you must retain this notice and the following
//  text and disclaimers in all such redistributions of the Daqri Software.
//  Neither the name, trademarks, service marks or logos of Daqri LLC may
//  be used to endorse or promote products derived from the Daqri Software
//  without specific prior written permission from Daqri.  Except as
//  expressly stated in this notice, no other rights or licenses, express or
//  implied, are granted by Daqri herein, including but not limited to any
//  patent rights that may be infringed by your derivative works or by other
//  works in which the Daqri Software may be incorporated.
//
//  The Daqri Software is provided by Daqri on an "AS IS" basis.  DAQRI
//  MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
//  THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
//  FOR A PARTICULAR PURPOSE, REGARDING THE DAQRI SOFTWARE OR ITS USE AND
//  OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
//
//  IN NO EVENT SHALL DAQRI BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
//  OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
//  MODIFICATION AND/OR DISTRIBUTION OF THE DAQRI SOFTWARE, HOWEVER CAUSED
//  AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
//  STRICT LIABILITY OR OTHERWISE, EVEN IF DAQRI HAS BEEN ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
//
//  Copyright 2015 Daqri LLC. All Rights Reserved.
//  Copyright 2010-2015 ARToolworks, Inc. All rights reserved.
//
//  Author(s): Philip Lamb
//
//#define DEBUG
//#define AR_INPUT_IPHONE 1
#import "ARViewController.h"
#import "PhotoView.h"
#import "ARView.h"
#import <AR/gsub_es.h>
#import <AudioToolbox/AudioToolbox.h> // SystemSoundID, AudioServicesCreateSystemSoundID()
//#import "NSMutableArray+Queue.h"
#import "ARAppES1-Swift.h"
#define VIEW_SCALEFACTOR        1.0f
#define VIEW_DISTANCE_MIN        5.0f          // Objects closer to the camera than this will not be displayed.
#define VIEW_DISTANCE_MAX        2000.0f        // Objects further away from the camera than this will not be displayed.

#define BUFFER_SIZE 10  //frame during in queue
#define SAMPLE_RATE 4
#define DISTANCE (14.7f/size)
#define BUFFER_DISTANCE 6.0f
//
// ARViewController
//


@implementation ARViewController {
    MotionKit *motionKit;
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
    NSMutableArray *queue[5];
//    struct recordType{
//        float pos[2];
//        float vector[4][2];
//    }record[100];
//    int recordNum ;
    int index;
    NSTimeInterval time;
    CGPoint accuPoint[5];
    float accumulate;
    CGPoint offset;
//    float filter[10];
    CGPoint predictPoint[5];
    NSMutableString *message ;
    float size;// 1m : 15.3   2m : 7.6 for iPad  //1m : 14.7  for iPhone6_Plus
    
}

@synthesize glView;
@synthesize arglContextSettings;
@synthesize running, runLoopInterval;

/*
 // The designated initializer.  Override if you create the controller programmatically and want to perform customization that is not appropriate for viewDidLoad.
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        // Custom initialization
    }
    return self;
}
*/

- (void)loadView
{
//    self.wantsFullScreenLayout = YES;
    
    // This will be replaced with the actual AR view.
    NSString *irisImage = nil;
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        irisImage = @"Iris-iPad.png";
    }  else { // UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone
        CGSize result = [[UIScreen mainScreen] bounds].size;
        if (result.height == 568) {
             irisImage = @"Iris-568h.png"; // iPhone 5, iPod touch 5th Gen, etc.
        } else { // result.height == 480
            irisImage = @"Iris.png";
        }
    }
    self.view = [[[UIImageView alloc] initWithImage:[UIImage imageNamed:irisImage]] autorelease]; // autorelease because self.view retains it.
}

// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Init instance variables.
    glView = nil;
    gVid = NULL;
    gCparamLT = NULL;
    gARHandle = NULL;
    gARPattHandle = NULL;
    gCallCountMarkerDetect = 0;
    gAR3DHandle = NULL;
    useContPoseEstimation = FALSE;
    arglContextSettings = NULL;
    running = FALSE;
    videoPaused = FALSE;
    runLoopTimePrevious = CFAbsoluteTimeGetCurrent();
    for (int i=0; i<5; i++) {
            queue[i] = [[NSMutableArray alloc] init];
    }
    index = 0;
    NSTimeInterval time=[[NSDate date] timeIntervalSince1970];
    motionKit=[[MotionKit alloc]init];
    motionKit.delegate=self;
    
    
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(orientationChanged:)
     name:UIDeviceOrientationDidChangeNotification
     object:[UIDevice currentDevice]];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self start];
}

// On iOS 6.0 and later, we must explicitly report which orientations this view controller supports.
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

- (void) setRunLoopInterval:(NSInteger)interval
{
    if (interval >= 1) {
        runLoopInterval = interval;
        if (running) {
            [self stopRunLoop];
            [self startRunLoop];
        }
    }
}

- (BOOL) isPaused
{
    if (!running) return (NO);

    return (videoPaused);
}

- (void) setPaused:(BOOL)paused
{
    if (!running) return;
    
    if (videoPaused != paused) {
        if (paused) ar2VideoCapStop(gVid);
        else ar2VideoCapStart(gVid);
        videoPaused = paused;
#  ifdef DEBUG
        NSLog(@"Run loop was %s.\n", (paused ? "PAUSED" : "UNPAUSED"));
#  endif
    }
}

static void startCallback(void *userData);

- (IBAction)start
{
    // Open the video path.
    char *vconf = ""; // See http://www.artoolworks.com/support/library/Configuring_video_capture_in_ARToolKit_Professional#AR_VIDEO_DEVICE_IPHONE
    if (!(gVid = ar2VideoOpenAsync(vconf, startCallback, self))) {
        NSLog(@"Error: Unable to open connection to camera.\n");
        [self stop];
        return;
    }
}

static void startCallback(void *userData)
{
    ARViewController *vc = (ARViewController *)userData;
    
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
//        char cparam_name[] = "Data2/camera_para.dat";
//        NSLog(@"Unable to automatically determine camera parameters. Using default.\n");
//        if (arParamLoad(cparam_name, 1, &cparam) < 0) {
//            NSLog(@"Error: Unable to load parameter file %s for camera.\n", cparam_name);
//            [self stop];
//            return;
//        }
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
//    arSetMarkerExtractionMode(gARHandle, AR_USE_TRACKING_HISTORY_V2);
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
     char *patt_name  = "Data2/marker16.pat";
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

- (void) cameraVideoTookPicture:(id)sender userData:(void *)data
{
    AR2VideoBufferT *buffer = ar2VideoGetImage(gVid);
    if (buffer) [self processFrame:buffer];
}

- (void) processFrame:(AR2VideoBufferT *)buffer
{
    ARdouble err;
    int j, k;
    CGPoint pos,vertex[4];
    float filter[10] = {0.25f,0.125f,0.125f,0.125f,0.0625f,0.0625f,0.0625f,0.0625f,0.0625f,0.0625f};

    if (buffer) {
        
        // Upload the frame to OpenGL.
        if (buffer->bufPlaneCount == 2) arglPixelBufferDataUploadBiPlanar(arglContextSettings, buffer->bufPlanes[0], buffer->bufPlanes[1]);
        else arglPixelBufferDataUpload(arglContextSettings, buffer->buff);
        
        gCallCountMarkerDetect++; // Increment ARToolKit FPS counter.
#ifdef DEBUG
        NSLog(@"video frame %ld.\n", gCallCountMarkerDetect);
#endif
#ifdef DEBUG
        if (gCallCountMarkerDetect % 150 == 0) {
            NSLog(@"*** Camera - %f (frame/sec)\n", (double)gCallCountMarkerDetect/arUtilTimer());
            gCallCountMarkerDetect = 0;
            arUtilTimerReset();            
        }
#endif
        
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
            //my_code
            //put point into queue
            if ( UIDeviceOrientationIsLandscape([UIDevice currentDevice].orientation)){
                index = 0;
                for (int i=0; i<5; i++) {
                    [queue[i] removeAllObjects];
                }
            }
            else {
                if ([[NSDate date]timeIntervalSince1970]-time>(1.0/SAMPLE_RATE)) {
                    
                    time = [[NSDate date]timeIntervalSince1970];
                    pos = CGPointMake(gARHandle->markerInfo[k].pos[0], gARHandle->markerInfo[k].pos[1]);
                    [queue[0] addObject:[NSValue valueWithCGPoint:pos]];
                    for (int i=0; i<4; i++) {
                        vertex[i] = CGPointMake(gARHandle->markerInfo[k].vertex[i][0],gARHandle->markerInfo[k].vertex[i][1]);
                        [queue[i+1] addObject:[NSValue valueWithCGPoint:vertex[i]]];
                    }
                    index++;
                    //get during point from queue
                    accumulate=0.0f;
                    for (int j=0; j<5; j++) {
                        accuPoint[j].x = 0.0f;
                        accuPoint[j].y = 0.0f;
                    }
                    for (int i=0; (i<index)&&(i<BUFFER_SIZE ); i++) {
                        for (int j=0; j<5; j++) {
                            accuPoint[j].x += ([[queue[j] objectAtIndex:index-i-1] CGPointValue].x * filter[i]);
                            accuPoint[j].y += [[queue[j] objectAtIndex:index-i-1] CGPointValue].y * filter[i];
                            accumulate += filter[i];
                        }
                    }
                    
                    for(int j=0;j<5;j++){
                        predictPoint[j].x = accuPoint[j].x/accumulate;
                        predictPoint[j].y = accuPoint[j].y/accumulate;
                    }
                    size = sqrtf(powf((predictPoint[4].x-predictPoint[2].x),2)+powf((predictPoint[4].x-predictPoint[2].x), 2));
                    NSLog(@"\npos:%@ \nvertex[0]:%@ \nvertex[1]:%@ \nvertex[2]:%@ \nvertex[3]:%@ \nsize:%f \ndistance:%f",NSStringFromCGPoint(predictPoint[0]),NSStringFromCGPoint(predictPoint[1]),NSStringFromCGPoint(predictPoint[2]),NSStringFromCGPoint(predictPoint[3]),NSStringFromCGPoint(predictPoint[4]),size,DISTANCE);
                    if (predictPoint[0].y-36>BUFFER_DISTANCE) {
                        NSLog(@"drone should go right.\n");
                    }
                    else if(predictPoint[0].y-36<(-BUFFER_DISTANCE)){
                        NSLog(@"drone should go left.\n");
                    }
                    else{
                        if (predictPoint[0].x-45>BUFFER_DISTANCE) {
                            NSLog(@"drone should go up.\n");
                        }
                        else if(predictPoint[0].x-45<(-BUFFER_DISTANCE)){
                            NSLog(@"drone should go down.\n");
                        }

                    }
                    //                    NSLog(@"%f",[[NSDate date]timeIntervalSince1970]);
                    //                    NSLog(@"index:%d",index);
                    //            for (int i=0; i<4; i++) {
                    //                for (int j=0; j<2; j++) {
                    //                    [queue[i+1][j] enqueue:@gARHandle->markerInfo[k].vertex[i][j]];
                    //                }
                    //            }
                    //            printf("pos:%f %f\n",gARHandle->markerInfo[k].pos[0],gARHandle->markerInfo[k].pos[1]);
                    //            for (int i=0; i<4; i++) {
                    //                printf("vector[%d] x:%f y:%f\n",i,gARHandle->markerInfo[k].vertex[i][0],gARHandle->markerInfo[k].vertex[i][1]);
                    //            }
                    //            //Log out drone position
                    //            if (gARHandle->markerInfo[k].pos[0]>240) {
                    //                NSLog(@"drone is under the center\n");
                    //            }
                    //            else NSLog(@"drone is upon the center\n");
                    //            if (gARHandle->markerInfo[k].pos[1]>180) {
                    //                NSLog(@"drone in left\n");
                    //            }
                    //            else NSLog(@"drone in right\n");
                }
            }
            //my_code end

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
            gPatt_found = TRUE;
            [glView setCameraPose:modelview]; //draw ar cube
        } else {
            gPatt_found = FALSE;
            [glView setCameraPose:NULL];
        }
        
        // Get current time (units = seconds).
        NSTimeInterval runLoopTimeNow;
        runLoopTimeNow = CFAbsoluteTimeGetCurrent();
        [glView updateWithTimeDelta:(runLoopTimeNow - runLoopTimePrevious)];
        
        // The display has changed.
        [glView drawView:self];
        
        // Save timestamp for next loop.
        runLoopTimePrevious = runLoopTimeNow;
    }
}

- (IBAction)stop
{
    [self stopRunLoop];
    for (int i=0; i<5; i++) {
        [queue[i] release];
    }
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
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}

- (void)viewWillDisappear:(BOOL)animated {
    [self stop];
    [super viewWillDisappear:animated];
}

- (void)dealloc {
    [super dealloc];
}

// ARToolKit-specific methods.
- (BOOL)markersHaveWhiteBorders
{
    int mode;
    arGetLabelingMode(gARHandle, &mode);
    return (mode == AR_LABELING_WHITE_REGION);
}

- (void)setMarkersHaveWhiteBorders:(BOOL)markersHaveWhiteBorders
{
    arSetLabelingMode(gARHandle, (markersHaveWhiteBorders ? AR_LABELING_WHITE_REGION : AR_LABELING_BLACK_REGION));
}


// Call this method to take a snapshot of the ARView.
// Once the image is ready, tookSnapshot:forview: will be called.
- (void)takeSnapshot
{
    // We will need to wait for OpenGL rendering to complete.
    [glView setTookSnapshotDelegate:self];
    [glView takeSnapshot];
}

// Here you can choose what to do with the image.
// We will save it to the iOS camera roll.
- (void)tookSnapshot:(UIImage *)snapshot forView:(EAGLView *)view
{
    // First though, unset ourselves as delegate.
    [glView setTookSnapshotDelegate:nil];
        
    // Write image to camera roll.
    UIImageWriteToSavedPhotosAlbum(snapshot, self, @selector(image:didFinishSavingWithError:contextInfo:), NULL);
}

// Let the user know that the image was saved by playing a shutter sound,
// or if there was an error, put up an alert.
- (void) image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo
{
    if (!error) {
        SystemSoundID shutterSound;
        AudioServicesCreateSystemSoundID((CFURLRef)[[NSBundle mainBundle] URLForResource: @"slr_camera_shutter" withExtension: @"wav"], &shutterSound);
        AudioServicesPlaySystemSound(shutterSound);
    } else {
        NSString *titleString = @"Error saving screenshot";
        NSString *messageString = [error localizedDescription];
        NSString *moreString = [error localizedFailureReason] ? [error localizedFailureReason] : NSLocalizedString(@"Please try again.", nil);
        messageString = [NSString stringWithFormat:@"%@. %@", messageString, moreString];
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:titleString message:messageString delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alertView show];
        [alertView release];
    }
}

- (void) orientationChanged:(NSNotification *)note{
    UIDevice *device = [UIDevice currentDevice];
    PhotoView *view2 = [[PhotoView alloc]init];
    //ViewController *view = [[ViewController alloc]init];
    
    
    switch(device.orientation)
    {
        case UIDeviceOrientationPortrait:
            [self dismissModalViewControllerAnimated:NO];
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            //_button.hidden = YES;
            break;
        case UIDeviceOrientationLandscapeLeft:
            NSLog (@"this is a test1");
            [self presentViewController:view2 animated:NO completion:nil];
            break;
        case UIDeviceOrientationLandscapeRight:
            NSLog (@"this is a test2");
            [self presentViewController:view2 animated:NO completion:nil];
            break;
            
        default:
            break;
    };
}

@end
