//
//  STKInputStreamDataSource.h
//  StreamingKit
//
//  Created by Aleksandr Smirnov on 29.03.17.
//  Copyright © 2017 Thong Nguyen. All rights reserved.
//

#import "STKCoreFoundationDataSource.h"

@interface STKInputStreamDataSource : STKCoreFoundationDataSource

- (instancetype)initWithStream: (CFReadStreamRef)readStream;

@end

