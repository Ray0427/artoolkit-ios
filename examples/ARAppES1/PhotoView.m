//
//  PhotoView.m
//  ARToolKit5iOS
//
//  Created by iuimini5 on 2015/5/30.
//
//

#import "PhotoView.h"
#import <SafariServices/SafariServices.h>

@implementation PhotoView
- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    NSString *urlString = @"http://192.168.1.2:5555/";
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLRequest *urlRequest = [NSURLRequest requestWithURL:url];
    [_webview2 loadRequest:urlRequest];
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)dealloc {
    [_webview2 release];
    [super dealloc];
}

- (IBAction)capture:(id)sender {
//    [_webview2 reload];
    UIGraphicsBeginImageContext(_webview2.frame.size);
    [_webview2.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage * viewImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    UIImageWriteToSavedPhotosAlbum(viewImage, nil, nil, nil);
    
    UIAlertView *alert = [[UIAlertView alloc]
                          initWithTitle:@"Captured "
                          message:nil
                          delegate:self
                          cancelButtonTitle:nil
                          otherButtonTitles:@"OK", nil];
    [alert show];
}
@end
