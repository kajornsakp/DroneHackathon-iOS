//
//  CameraPreviewViewController.m
//  MediaManagerDemo
//
//  Created by Kajornsak Peerapathananont on 11/17/2560 BE.
//  Copyright © 2560 DJI. All rights reserved.
//

#import "CameraPreviewViewController.h"
#import <GoogleMaps/GoogleMaps.h>
#import <FirebaseStorage/FirebaseStorage.h>
#import <FirebaseDatabase/FirebaseDatabase.h>
#import <VideoPreviewer/VideoPreviewer.h>
#import <DJISDK/DJISDK.h>
#import <CoreLocation/CoreLocation.h>
#import "DemoUtility.h"
#import <QuartzCore/QuartzCore.h>
#import "MissionCollectionViewCell.h"
#import "PotHoleCollectionViewCell.h"
#import "DemoComponentHelper.h"
@interface CameraPreviewViewController ()<DJIVideoFeedListener,DJISDKManagerDelegate,DJICameraDelegate,CLLocationManagerDelegate,GMSMapViewDelegate,UICollectionViewDelegate,UICollectionViewDataSource,DJIFlightControllerDelegate>
@property (weak, nonatomic) IBOutlet UILabel *statusLabel;
@property (weak, nonatomic) IBOutlet UICollectionView *missionCollectionView;
@property (strong, nonatomic) IBOutlet GMSMapView *mapView;
@property (weak, nonatomic) IBOutlet UIView *fpsView;
@property (weak, nonatomic) IBOutlet UIImageView *imagePreview;
@property (strong,nonatomic) FIRDatabaseReference *ref;
@property (weak, nonatomic) IBOutlet UICollectionView *potHoleCollectionView;
@property (weak, nonatomic) IBOutlet UIButton *addButton;
@property(nonatomic,strong) NSMutableArray<GMSMarker *> *markerArray;
@property(nonatomic,strong) NSMutableArray *coordinateArray;
@property(nonatomic,strong) CLLocationManager *locationManager;
@property(nonatomic,strong) FIRStorage *storage;
@property(nonatomic,strong) FIRStorageReference *storageRef;
@property(nonatomic,strong) FIRDatabaseReference *dataRef;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,strong) NSMutableArray *potholeArray;
@property Boolean isAddable;
@property(nonatomic,strong) NSMutableArray *actions;
@property(nonatomic,strong) DJIMission *mission;
@property(nonatomic,assign) CLLocationCoordinate2D homeLocation;
@property(nonatomic,assign) CLLocationCoordinate2D aircraftLocation;
@property (weak, nonatomic) IBOutlet UIButton *startMissionButton;
@property(nonatomic,strong) NSString *fileName;
@property(nonatomic,strong) NSString *uid;

@end

@implementation CameraPreviewViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.mapView.delegate = self;
    self.missionCollectionView.delegate = self;
    self.missionCollectionView.dataSource = self;
    self.potHoleCollectionView.delegate = self;
    self.potHoleCollectionView.dataSource = self;
    self.coordinateArray = [[NSMutableArray alloc] init];
    self.potholeArray = [[NSMutableArray alloc] init];
    self.markerArray = [[NSMutableArray alloc] init];
    self.actions = [[NSMutableArray alloc] init];
    self.storage = [FIRStorage storage];
    self.storageRef = [self.storage reference];
    self.ref = [[FIRDatabase database] reference];
    self.dataRef = [[self.ref child:@"messages"] child:@"data"];
    //self.timer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(getImageFromPreview) userInfo:nil repeats:NO];
    self.isAddable = NO;
}
-(void)getImageFromPreview{
//    NSLog(@"get image");
    UIImage *image = [self imageWithView:self.fpsView];
    [self.imagePreview setImage:image];
    [self uploadData: UIImageJPEGRepresentation(image,0.5)];
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewDidAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    GMSCameraPosition *camera = [GMSCameraPosition cameraWithLatitude:-33.86 longitude:151.20 zoom:6];
    self.mapView = [GMSMapView mapWithFrame:CGRectZero camera:camera];
    self.mapView.myLocationEnabled = YES;
    self.mapView.settings.myLocationButton = YES;
    [self setupVideoPreviewer];
    [self.locationManager requestWhenInUseAuthorization];
    [self.locationManager startUpdatingLocation];
    [self.dataRef observeEventType:FIRDataEventTypeChildAdded withBlock:^(FIRDataSnapshot * _Nonnull snapshot) {
        [self.potholeArray addObject:snapshot];
        [self.potHoleCollectionView reloadData];
    }];
    if ([DemoComponentHelper fetchAircraft] != nil) { // the product is an aircraft
        if ([DemoComponentHelper fetchFlightController]) {
            [[DemoComponentHelper fetchFlightController] setDelegate:self];
        }
    }
    [self.startMissionButton setEnabled:CLLocationCoordinate2DIsValid(self.homeLocation)];
}

- (void)setupVideoPreviewer{
    [[VideoPreviewer instance]setView:self.fpsView];
    DJIBaseProduct *product = [DJISDKManager product];
    if ([product.model isEqual:DJIAircraftModelNameA3] ||
        [product.model isEqual:DJIAircraftModelNameN3] ||
        [product.model isEqual:DJIAircraftModelNameMatrice600] ||
        [product.model isEqual:DJIAircraftModelNameMatrice600Pro]){
        [[DJISDKManager videoFeeder].secondaryVideoFeed addListener:self withQueue:nil];
    }else{
        [[DJISDKManager videoFeeder].primaryVideoFeed addListener:self withQueue:nil];
    }
    [[VideoPreviewer instance] start];
    
}

- (void)resetVideoPreview {
    [[VideoPreviewer instance] unSetView];
    DJIBaseProduct *product = [DJISDKManager product];
    if ([product.model isEqual:DJIAircraftModelNameA3] ||
        [product.model isEqual:DJIAircraftModelNameN3] ||
        [product.model isEqual:DJIAircraftModelNameMatrice600] ||
        [product.model isEqual:DJIAircraftModelNameMatrice600Pro]){
        [[DJISDKManager videoFeeder].secondaryVideoFeed removeListener:self];
    }else{
        [[DJISDKManager videoFeeder].primaryVideoFeed removeListener:self];
    }
}

- (DJICamera*) fetchCamera {
    
    if (![DJISDKManager product]) {
        return nil;
    }
    
    if ([[DJISDKManager product] isKindOfClass:[DJIAircraft class]]) {
        return ((DJIAircraft*)[DJISDKManager product]).camera;
    }else if ([[DJISDKManager product] isKindOfClass:[DJIHandheld class]]){
        return ((DJIHandheld *)[DJISDKManager product]).camera;
    }
    
    return nil;
}
#pragma mark DJISDKManagerDelegate Method
- (void)productConnected:(DJIBaseProduct *)product
{
    if(product){
        [product setDelegate:self];
        DJICamera *camera = [self fetchCamera];
        if (camera != nil) {
            camera.delegate = self;
        }
        [self setupVideoPreviewer];
    }
}
- (void)productDisconnected
{
    DJICamera *camera = [self fetchCamera];
    if (camera && camera.delegate == self) {
        [camera setDelegate:nil];
    }
    [self resetVideoPreview];
    
}
- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    DJICamera *camera = [self fetchCamera];
    if (camera && camera.delegate == self) {
        [camera setDelegate:nil];
    }
    [self resetVideoPreview];
    [self.locationManager stopUpdatingLocation];
    if ([DemoComponentHelper fetchAircraft] != nil) { // the product is an aircraft
        DJIFlightController* flightController = [DemoComponentHelper fetchFlightController];
        if (flightController != nil && flightController.delegate == self) {
            [flightController setDelegate:nil];
        }
    }
}

#pragma mark - DJIVideoFeedListener
-(void)videoFeed:(DJIVideoFeed *)videoFeed didUpdateVideoData:(NSData *)videoData {
    [[VideoPreviewer instance] push:(uint8_t *)videoData.bytes length:(int)videoData.length];
}
#pragma mark - DJICameraDelegate
-(void) camera:(DJICamera*)camera didUpdateSystemState:(DJICameraSystemState*)systemState
{
}

#pragma mark - Mission Command Action

- (IBAction)getCurrentLocation:(id)sender {
//    NSLog(@"get location");
    [self.locationManager requestLocation];
}

#pragma mark -location delegate
-(void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations{
    CLLocation *location = [locations lastObject];
    GMSCameraPosition *camera = [GMSCameraPosition cameraWithLatitude:location.coordinate.latitude longitude:location.coordinate.longitude zoom:10];
//    NSLog(@"%@",self.mapView);
    [self animateToPosition:camera];
//    NSLog(@"location : %@",location);
}
-(void)animateToPosition:(GMSCameraPosition*)camera{
    [self.mapView setCamera:camera];
}
-(void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error{
    NSLog(@"Error : %@",error);
}
- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status{
    if(status == kCLAuthorizationStatusAuthorizedWhenInUse){
        self.mapView.myLocationEnabled = YES;
        self.mapView.settings.myLocationButton = YES;
    }
}
#pragma mark gms mapview delegate
-(void)mapView:(GMSMapView *)mapView didTapAtCoordinate:(CLLocationCoordinate2D)coordinate{
    if (self.isAddable) {
        [self.coordinateArray addObject: [NSValue valueWithBytes:&coordinate objCType:@encode(CLLocationCoordinate2D)]];
        [self updateMapUI:mapView];
    }
}

-(void)updateMapUI:(GMSMapView *)mapView{
    for(NSValue *value in self.coordinateArray){
        CLLocationCoordinate2D coordinate;
        [value getValue:&coordinate];
        GMSMarker *marker = [GMSMarker markerWithPosition:coordinate];
        marker.map = mapView;
        [self.markerArray addObject:marker];
    }
}
#pragma mark collection view delegate
-(NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section{
    if (collectionView == _missionCollectionView) {
        return 2;
    }else if(collectionView == _potHoleCollectionView){
        return self.potholeArray.count;
    }
    return 0;
}

-(UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath{
    if (collectionView == _missionCollectionView) {
        static NSString *identifier = @"missionCell";
        MissionCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:identifier forIndexPath:indexPath];
        [cell setBackgroundColor:[UIColor blackColor]];
        return cell;
    }else if(collectionView == _potHoleCollectionView){
        static NSString *identifier = @"potHoleCell";
        PotHoleCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:identifier forIndexPath:indexPath];
        FIRDataSnapshot *snapshot = [self.potholeArray objectAtIndex:indexPath.row];
        NSLog(@"%@",snapshot);
        NSDictionary *snapshotDict = snapshot.value;
        NSString *filename = snapshotDict[@"name"];
        NSString *urlPath = snapshotDict[@"url"];
        NSURL *url = [NSURL URLWithString:urlPath];
        NSData *data = [NSData dataWithContentsOfURL:url];
        UIImage *image = [UIImage imageWithData:data];
        [cell.potHoleImage setImage:image];
        [cell.potHoleLabel setText:filename];
        [cell setBackgroundColor:[UIColor blackColor]];
        
        return cell;
    }
    return [[UICollectionViewCell alloc] init];
}


#pragma mark firebase storage
-(void)uploadData:(NSData*)data{
//    NSLog(@"%@",data);
    if(CLLocationCoordinate2DIsValid(self.aircraftLocation)){
    NSDate *currentDate = [NSDate date];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"ddMMYY-HH:mm:ss"];
    NSString *coordinate = [NSString stringWithFormat:@"%.4f_%.4f",self.aircraftLocation.latitude,self.aircraftLocation.longitude];
    coordinate = [coordinate stringByReplacingOccurrencesOfString:@"." withString:@","];
    NSString *dateString = [dateFormatter stringFromDate:currentDate];
    NSMutableString *file = [NSMutableString stringWithString:dateString];
    [file appendString:coordinate];
    [file appendString:@".jpeg"];
    FIRStorageReference *imageRef = [self.storageRef child:file];
    FIRStorageMetadata *metadata = [[FIRStorageMetadata alloc] init];
    metadata.contentType = @"image/jpeg";
    FIRStorageUploadTask *uploadTask = [imageRef putData:data metadata:metadata completion:^(FIRStorageMetadata *metadata,NSError *error){
        if(error != nil){
            ShowResult(@"Error : %@",error.localizedDescription);
        }
        else{
            NSLog(@"upload data success : %@",metadata);
            ShowResult(@"upload success :%@",metadata);
        }
    }];
    }
}
#pragma mark uploadToRealtimeDB
-(void)uploadToRealtimeDB:(NSString*)fileName{

    if(CLLocationCoordinate2DIsValid(self.aircraftLocation))
    {
        NSString *coordinate = [NSString stringWithFormat:@"lat : %.4f long : %.4f",self.aircraftLocation.latitude,self.aircraftLocation.longitude];
        NSLog(@"%@",coordinate);
        
        [[self.dataRef child:fileName] setValue:@"coordinate" forKey:coordinate];
    }
}
#pragma mark take picture
- (IBAction)selectorcaptureAction:(id)sender{
    [self getImageFromPreview];
}


-(UIImage *) imageWithView:(UIView *)view
{
    UIGraphicsBeginImageContextWithOptions(view.bounds.size, view.opaque, 0.0f);
    [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:NO];
    UIImage * snapshotImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return snapshotImage;
}

- (IBAction)didTapClearPath:(id)sender {
    for (GMSMarker *marker in _markerArray) {
        marker.map = nil;
    }
    [self.markerArray removeAllObjects];
    [self.coordinateArray removeAllObjects];
    [self.mapView clear];
//    NSLog(@"%@",_markerArray);
//    NSLog(@"%@",_coordinateArray);
//    NSLog(@"CLEAR");
}

- (IBAction)didTapEditPath:(id)sender {
    self.isAddable = !_isAddable;
}

-(void)updateButtonUI{
    if (!self.isAddable) {
        [self.addButton.titleLabel setText:@"Done"];
    }else{
        [self.addButton.titleLabel setText:@"Add path"];
    }
}
- (IBAction)didTapStartMission:(id)sender {
    self.mission = [self initializeMission];
    if(self.mission == nil) return;
    [[DJISDKManager missionControl] addListener:self toTimelineProgressWithBlock:^(DJIMissionControlTimelineEvent event, id<DJIMissionControlTimelineElement>  _Nullable element, NSError * _Nullable error, id  _Nullable info) {
        NSMutableString *statusStr = [NSMutableString new];
        [statusStr appendFormat:@"Current Event:%@", [[self class] timelineEventString:event]];
        [statusStr appendFormat:@"Element:%@", [element description]];
        [statusStr appendFormat:@"Info:%@", info];
        if (error) {
            [statusStr appendFormat:@"Error:%@", error.description];
        }
        self.statusLabel.text = statusStr;
        if (error) {
            [[DJISDKManager missionControl] stopTimeline];
            [[DJISDKManager missionControl] unscheduleEverything];
        }
    }];
        [[DJISDKManager missionControl] startTimeline];
}
- (IBAction)didTapStopMission:(id)sender {
    [[DJISDKManager missionControl] stopTimeline];
    [[DJISDKManager missionControl] unscheduleEverything];
    [[DJISDKManager missionControl] removeListener:self];
}
-(void)initWaypoint{
    DJIMutableWaypointMission *mission = [[DJIMutableWaypointMission alloc] init];
}

-(void)flightController:(DJIFlightController *)fc didUpdateState:(DJIFlightControllerState *)state {
    self.aircraftLocation = state.aircraftLocation.coordinate;
    self.homeLocation = state.homeLocation.coordinate;
}
-(DJIMission*) initializeMission {
    return [[DJIMission alloc] init];
}
- (IBAction)didTapPrepare:(id)sender {
    [self initializeActions];
    NSError *error = [[DJISDKManager missionControl] scheduleElements:self.actions];
    if (error) {
        ShowResult(@"Schedule Timeline Actions Failed:%@", error.description);
    } else {
        ShowResult(@"Actions schedule succeed!");
    }
}
-(void) initializeActions {
    if (self.actions == nil) {
        self.actions = [[NSMutableArray alloc] init];
    }
    
    // Step 1: take off from the ground
    DJITakeOffAction* takeoffAction = [[DJITakeOffAction alloc] init];
    [self.actions addObject:takeoffAction];
    
    // Step 5: start a waypoint mission while the aircraft is still recording the video
    DJIWaypointMission *waypointAction = [self initializeWaypointMissonStep];
    [self.actions addObject:waypointAction];
    
    // Step 2: reset the gimbal to horizontal angle
    DJIGimbalAttitude atti = {-10, 0, 0};
    DJIGimbalAttitudeAction* gimbalAttiAction = [[DJIGimbalAttitudeAction alloc] initWithAttitude:atti];
    [self.actions addObject:gimbalAttiAction];
    

    // Step 8: go back home
    DJIGoHomeAction* gohomeAction = [[DJIGoHomeAction alloc] init];
    [self.actions addObject:gohomeAction];
}

- (DJIWaypointMission*)initializeWaypointMissonStep {
    DJIMutableWaypointMission* mission = [[DJIMutableWaypointMission alloc] init];
    
    // prepare waypoint
    
    CLLocationDegrees currentLatitude = self.aircraftLocation.latitude;
    CLLocationDegrees currentLongitude = self.aircraftLocation.longitude;
    
    for(NSValue *value in self.coordinateArray){
        CLLocationCoordinate2D coordinate;
        [value getValue:&coordinate];
        DJIWaypoint *targetPoint = [[DJIWaypoint alloc] initWithCoordinate:coordinate];
        [mission addWaypoint:targetPoint];
        
    }
    
    [mission setFinishedAction:DJIWaypointMissionFinishedNoAction];
    
    DJIWaypointMission* action = [[DJIWaypointMission alloc] initWithMission:mission];
    
    return action;
}

+ (NSString*)timelineEventString:(DJIMissionControlTimelineEvent)event
{
    NSString *eventString = @"N/A";
    
    switch (event) {
        case DJIMissionControlTimelineEventPaused:
            eventString = @"Paused";
            break;
        case DJIMissionControlTimelineEventResumed:
            eventString = @"Resumed";
            break;
        case DJIMissionControlTimelineEventStarted:
            eventString = @"Started";
            break;
        case DJIMissionControlTimelineEventStopped:
            eventString = @"Stopped";
            break;
        case DJIMissionControlTimelineEventFinished:
            eventString = @"Finished";
            break;
        case DJIMissionControlTimelineEventStopError:
            eventString = @"Stop Error";
            break;
        case DJIMissionControlTimelineEventPauseError:
            eventString = @"Pause Error";
            break;
        case DJIMissionControlTimelineEventProgressed:
            eventString = @"Progressed";
            break;
        case DJIMissionControlTimelineEventStartError:
            eventString = @"Start Error";
            break;
        case DJIMissionControlTimelineEventResumeError:
            eventString = @"Resume Error";
            break;
        case DJIMissionControlTimelineEventUnknown:
            eventString = @"Unknown";
            break;
        default:
            break;
    }
    return eventString;
}

@end



//TODO: send waypoint to drone
//TODO: get lat long from drone
//TODO: send waypoint to drone

//+13.67003300,+100.61036400
