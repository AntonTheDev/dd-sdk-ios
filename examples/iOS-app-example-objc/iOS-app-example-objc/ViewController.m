/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

#import "ViewController.h"
@import DatadogObjc;
#import <DatadogCrashes/DDDatadogCrashes.h>

@interface ViewController ()

@property (nonatomic, nonnull) DDLogger *logger;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    DDLoggerBuilder *loggerBuilder = [DDLogger builder];
    [loggerBuilder setWithServiceName: @"ios-sdk-example-app"];
    [loggerBuilder sendLogsToDatadog: YES];
    [loggerBuilder printLogsToConsole: YES];

    [DDDatadogCrashes enable];

    self.logger = [loggerBuilder build];
}

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.logger debug: @"viewDidLoad"];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.logger debug: @"viewDidAppear"];
}

- (IBAction)didTapButton:(id)sender {
    UIButton *button = sender;

    [self.logger info: @"button tapped" attributes: @{
        @"button-info": @{
            @"label": button.titleLabel.text,
            @"size": @{
                @"width": [NSNumber numberWithFloat: button.frame.size.width],
                @"height": [NSNumber numberWithFloat: button.frame.size.height]
            }
        },
    }];
}

- (IBAction)didTapCrash:(id)sender {
    NSMutableArray *integers = [NSMutableArray array];

    for (NSInteger i = 0; i < 40; i++) {
        [integers addObject:[NSNumber numberWithInteger:i]];
    }

    NSLog(@"The 41st integer is: %@", [integers objectAtIndex: 41]);
}

@end
