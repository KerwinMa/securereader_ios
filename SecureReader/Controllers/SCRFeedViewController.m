//
//  SRMainViewController.m
//  SecureReader
//
//  Created by N-Pex on 2014-10-27.
//  Copyright (c) 2014 Guardian Project. All rights reserved.
//

#import "SCRFeedViewController.h"
#import "SCRItem.h"
#import "SCRItemView.h"
#import "SCRFeedFetcher.h"
#import "YapDatabase.h"
#import "SCRDatabaseManager.h"
#import "YapDatabaseView.h"
#import "UIImageView+AFNetworking.h"
#import "SCRItemViewController.h"
#import "SCRItemViewControllerSegue.h"
#import "SCRAppDelegate.h"
#import "NSFormatter+SecureReader.h"
#import "SCRNavigationController.h"

@interface SCRFeedViewController ()

// Prototype cells for height calculation
@property (nonatomic, strong) SCRItemView *prototypeCellNoPhotos;
@property (nonatomic, strong) SCRItemView *prototypeCellLandscapePhotos;
@property (nonatomic, strong) SCRItemView *prototypeCellPortraitPhotos;

@property (strong,nonatomic) SCRItemViewController *itemViewController;

@property (nonatomic, strong) YapDatabaseViewMappings *mappings;
@property (nonatomic, strong) YapDatabaseConnection *readConnection;
@property (nonatomic, strong, readonly) NSString *yapViewName;

@property (nonatomic) SCRFeedViewType currentType;
@property (nonatomic, strong) SCRFeed *currentFeed;
@property (nonatomic) NSTimer *updateTimeStampTimer;

@end

@implementation SCRFeedViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    UINib *nib = [UINib nibWithNibName:@"SCRItemCellNoPhotos" bundle:nil];
    [self.tableView registerNib:nib forCellReuseIdentifier:@"cellNoPhotos"];
    nib = [UINib nibWithNibName:@"SCRItemCellLandscapePhotos" bundle:nil];
    [self.tableView registerNib:nib forCellReuseIdentifier:@"cellLandscapePhotos"];
    //UIRefreshControl *refreshControl = [[UIRefreshControl alloc]
    //                                    init];
    //refreshControl.tintColor = [UIColor magentaColor];
    //self.refreshControl = refreshControl;
}

- (void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [(SCRNavigationController *)self.navigationController registerScrollViewForHideBars:self.tableView];
    if ([[SCRAppDelegate sharedAppDelegate] isLoggedIn])
    {
        [self.tableView reloadData];
    }
    if (_updateTimeStampTimer != nil)
        [_updateTimeStampTimer invalidate];
    _updateTimeStampTimer = [NSTimer timerWithTimeInterval:60 target:self selector:@selector(updateTimeStampTimerDidFire) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_updateTimeStampTimer forMode:NSRunLoopCommonModes];
}

- (void)viewDidDisappear:(BOOL)animated
{
    if (_updateTimeStampTimer != nil)
        [_updateTimeStampTimer invalidate];
    _updateTimeStampTimer = nil;
}

- (void)viewWillAppear:(BOOL)animated
{
    [self.navigationController setNavigationBarHidden:NO];
}

- (void) setFeedViewType:(SCRFeedViewType)type feed:(SCRFeed *)feed
{
    switch (type) {
        case SCRFeedViewTypeAllFeeds:
            self.navigationItem.title = @"All feeds";
            break;
            
        case SCRFeedViewTypeFavorites:
            self.navigationItem.title = @"Favorites";
            break;
            
        case SCRFeedViewTypeFeed:
            if (feed != nil)
                self.navigationItem.title = feed.title;
            else
                self.navigationItem.title = @"Feed";
            break;
            
        case SCRFeedViewTypeReceived:
            self.navigationItem.title = @"Received";
            break;
            
        default:
            self.navigationItem.title = @"Feed";
            break;
    }

    self.currentType = type;
    self.currentFeed = feed;
    
    if (type == SCRFeedViewTypeFavorites)
        _yapViewName =  [SCRDatabaseManager sharedInstance].favoriteFeedItemsViewName;
    else if (type == SCRFeedViewTypeReceived)
        _yapViewName = [SCRDatabaseManager sharedInstance].receivedFeedItemsViewName;
    else
        _yapViewName = [SCRDatabaseManager sharedInstance].allFeedItemsViewName;
    [self setupMappings];
}

- (NSString *) getCellIdentifierForItem:(SCRItem *) item
{
    NSString *cellIdentifier = @"cellNoPhotos";
    if (item.thumbnailURL) {
        // perhaps we can also provide "cellPortraitPhotos" via thumbnailSize property
        cellIdentifier = @"cellLandscapePhotos";
    }
    return cellIdentifier;
}

- (SCRItemView *) getPrototypeForItem:(SCRItem *) item
{
    NSString *cellIdentifier = [self getCellIdentifierForItem:item];
    if ([cellIdentifier compare:@"cellLandscapePhotos"] == NSOrderedSame)
    {
        if (!self.prototypeCellLandscapePhotos)
            self.prototypeCellLandscapePhotos = [self.tableView dequeueReusableCellWithIdentifier:cellIdentifier];
        return self.prototypeCellLandscapePhotos;
    }
    else if ([cellIdentifier compare:@"cellPortraitPhotos"] == NSOrderedSame)
    {
        if (!self.prototypeCellPortraitPhotos)
            self.prototypeCellPortraitPhotos = [self.tableView dequeueReusableCellWithIdentifier:cellIdentifier];
        return self.prototypeCellPortraitPhotos;
    }
    else
    {
        // No photos
        if (!self.prototypeCellNoPhotos)
            self.prototypeCellNoPhotos = [self.tableView dequeueReusableCellWithIdentifier:cellIdentifier];
        return self.prototypeCellNoPhotos;
    }
}

#pragma mark UITableViewDelegate methods

- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    //if (self.itemViewController == nil)
    {
         self.itemViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"itemView"];
    }
    [self.itemViewController setDataView:self withStartAt:indexPath];
    SCRItemViewControllerSegue *segue = [[SCRItemViewControllerSegue alloc] initWithIdentifier:@"" source:self destination:self.itemViewController];
    [self prepareForSegue:segue sender:self];
    [segue perform];
}

#pragma mark UITableViewDataSource methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)sender
{
    NSInteger numberOfSections = [self.mappings numberOfSections];
    return numberOfSections;
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger numberOfRows = [self.mappings numberOfItemsInSection:section];
    return numberOfRows;
}

- (SCRItem *) itemForIndexPath:(NSIndexPath *) indexPath
{
    __block SCRItem *item = nil;
    [self.readConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        item = [[transaction extension:self.yapViewName] objectAtIndexPath:indexPath withMappings:self.mappings];
    }];
    return item;
}

- (void)configureCell:(SCRItemView *)cell forItem:(SCRItem *)item
{
    cell.titleView.text = item.title;
    cell.sourceView.labelSource.text = [item.linkURL host];
    cell.sourceView.labelDate.text = [[NSFormatter scr_sharedIntervalFormatter] stringForTimeIntervalFromDate:[NSDate date] toDate:item.publicationDate];
    cell.imageView.image = nil;
    if (item.thumbnailURL) {
        [cell.imageView setImageWithURL:item.thumbnailURL];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    SCRItem *item = [self itemForIndexPath:indexPath];
    
    NSString *cellIdentifier = [self getCellIdentifierForItem:item];
    
    SCRItemView *cell = [tableView
                      dequeueReusableCellWithIdentifier:cellIdentifier forIndexPath:indexPath];
    [self configureCell:cell forItem:item];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 100;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    SCRItem *item = [self itemForIndexPath:indexPath];
    SCRItemView *prototype = [self getPrototypeForItem:item];
    [self configureCell:prototype forItem:item];
    prototype.bounds = CGRectMake(0.0f, 0.0f, CGRectGetWidth(tableView.bounds), CGRectGetHeight(prototype.bounds));
    [prototype setNeedsLayout];
    [prototype layoutIfNeeded];
    
    CGSize size = [prototype.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    return size.height+1;
}

#pragma mark YapDatabase

- (void) setupMappings {
    self.readConnection = [[SCRDatabaseManager sharedInstance].database newConnection];
    self.mappings = [[YapDatabaseViewMappings alloc] initWithGroupFilterBlock:^BOOL(NSString *group, YapDatabaseReadTransaction *transaction) {
        if (self.currentFeed != nil)
        {
            return [group isEqualToString:[self.currentFeed yapGroup]];
        }
        return YES;
    } sortBlock:^NSComparisonResult(NSString *group1, NSString *group2, YapDatabaseReadTransaction *transaction) {
        return [group1 compare:group2];
    } view:self.yapViewName];
    
    // Freeze our databaseConnection on the current commit.
    // This gives us a snapshot-in-time of the database,
    // and thus a stable data source for our UI thread.
    [self.readConnection beginLongLivedReadTransaction];
    
    // Initialize our mappings.
    // Note that we do this after we've started our database longLived transaction.
    [self.readConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){
        
        // Calling this for the first time will initialize the mappings,
        // and will allow mappings to cache certain information
        // such as the counts for each section.
        [self.mappings updateWithTransaction:transaction];
    }];
    
    // And register for notifications when the database changes.
    // Our method will be invoked on the main-thread,
    // and will allow us to move our stable data-source from our existing state to an updated state.
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModified:)
                                                 name:YapDatabaseModifiedNotification
                                               object:self.readConnection.database];
    
    [self.tableView reloadData];
}

- (void)yapDatabaseModified:(NSNotification *)notification
{
    // Jump to the most recent commit.
    // End & Re-Begin the long-lived transaction atomically.
    // Also grab all the notifications for all the commits that I jump.
    // If the UI is a bit backed up, I may jump multiple commits.
    
    NSArray *notifications = [self.readConnection beginLongLivedReadTransaction];
    
    // If the view isn't visible, we might decide to skip the UI animation stuff.
    if (!([self isViewLoaded] && self.view.window))
    {
        // Since we moved our databaseConnection to a new commit,
        // we need to update the mappings too.
        [self.readConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){
            [self.mappings updateWithTransaction:transaction];
        }];
        return;
    }
    
    // Process the notification(s),
    // and get the change-set(s) as applies to my view and mappings configuration.
    //
    // Note: the getSectionChanges:rowChanges:forNotifications:withMappings: method
    // automatically invokes the equivalent of [mappings updateWithTransaction:] for you.
    
    NSArray *sectionChanges = nil;
    NSArray *rowChanges = nil;
    
    [[self.readConnection ext:self.yapViewName] getSectionChanges:&sectionChanges
                                                       rowChanges:&rowChanges
                                                 forNotifications:notifications
                                                     withMappings:self.mappings];
    
    // No need to update mappings.
    // The above method did it automatically.
    
    if ([sectionChanges count] == 0 & [rowChanges count] == 0)
    {
        // Nothing has changed that affects our tableView
        return;
    }
    
    // If there are a lot of row changes, it is quicker to just call reloadData
    if ([rowChanges count] > 50) {
        [self.tableView reloadData];
        return;
    }
    
    [self.tableView beginUpdates];
    
    for (YapDatabaseViewSectionChange *sectionChange in sectionChanges)
    {
        switch (sectionChange.type)
        {
            case YapDatabaseViewChangeDelete :
            {
                [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:sectionChange.index]
                                       withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeInsert :
            {
                [self.tableView insertSections:[NSIndexSet indexSetWithIndex:sectionChange.index]
                                       withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeMove:
            {
                break;
            }
            case YapDatabaseViewChangeUpdate:
            {
                break;
            }
        }
    }
    
    for (YapDatabaseViewRowChange *rowChange in rowChanges)
    {
        switch (rowChange.type)
        {
            case YapDatabaseViewChangeDelete :
            {
                [self.tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
                                               withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeInsert :
            {
                [self.tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
                                               withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeMove :
            {
                [self.tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
                                               withRowAnimation:UITableViewRowAnimationAutomatic];
                [self.tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
                                               withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeUpdate :
            {
                [self.tableView reloadRowsAtIndexPaths:@[ rowChange.indexPath ]
                                               withRowAnimation:UITableViewRowAnimationNone];
                break;
            }
        }
    }
    
    [self.tableView endUpdates];
}

- (void)updateTimeStampTimerDidFire
{
    NSArray *visibleCells = [self.tableView visibleCells];
    for (SCRItemView *cell in visibleCells) {
        NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
        SCRItem *item = [self itemForIndexPath:indexPath];
        [self configureCell:cell forItem:item];
        [cell setNeedsLayout];
    }
}

@end
