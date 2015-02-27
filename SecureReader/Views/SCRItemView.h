//
//  ItemView.h
//  SecureReader
//
//  Created by N-Pex on 2014-09-11.
//  Copyright (c) 2014 Guardian Project. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SCRSourceView.h"
#import <SWTableViewCell.h>

@interface SCRItemView : SWTableViewCell

@property (weak, nonatomic) IBOutlet UIImageView *imageView;
@property (weak, nonatomic) IBOutlet SCRSourceView *sourceView;
@property (weak, nonatomic) IBOutlet UILabel *titleView;
@property (weak, nonatomic) IBOutlet UITextField *textView;

@end
