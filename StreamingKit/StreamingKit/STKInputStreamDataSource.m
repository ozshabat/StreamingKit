//
//  STKInputStreamDataSource.m
//  StreamingKit
//
//  Created by Aleksandr Smirnov on 29.03.17.
//  Copyright © 2017 Thong Nguyen. All rights reserved.
//

#import "STKInputStreamDataSource.h"
#import <MacTypes.h>

@interface STKInputStreamDataSource ()
{
    CFReadStreamRef inputStream;
    SInt64 position;
    SInt64 length;
    AudioFileTypeID _audioFileTypeHint;
}

@end

@implementation STKInputStreamDataSource

- (instancetype)initWithStream:(CFReadStreamRef)readStream {
    if (self = [super init])
    {
        inputStream = readStream;
        _audioFileTypeHint = kAudioFileAAC_ADTSType;
    }
    return self;
}

-(AudioFileTypeID) audioFileTypeHint
{
    return _audioFileTypeHint;
}

-(SInt64) position
{
    return position;
}

-(SInt64) length
{
    return length;
}

-(void) dealloc
{
    [self close];
}

-(void) close
{
    if (stream)
    {
        [self unregisterForEvents];
        
        CFReadStreamClose(stream);
        
        stream = 0;
    }
}

-(void) open
{
    if (stream)
    {
        [self unregisterForEvents];
        CFReadStreamClose(stream);
        CFRelease(stream);
        
        stream = 0;
    }
    
    stream = inputStream;
    
    if (stream) {
        [self reregisterForEvents];
        
        CFReadStreamOpen(stream);
    }
    
}

NSMutableData* adtsHeader;
uint64_t modifiedAdts;
NSMutableData* packetWithHeader;
//UInt8* tempBuffer;
UInt64 lastTimeStamp;

/// will build the adts header
-(void) buildHeader:(int)frameLength
{
    UInt64 test = frameLength + 7;
    modifiedAdts = 72041155050602496 | test << 13;
    modifiedAdts = CFSwapInt64(modifiedAdts) >> 8;
    adtsHeader = [NSMutableData dataWithBytes:&modifiedAdts length:7];
    
//    modifiedAdts = 72041155050602496 | UInt64(frameLength + 7) << 13
//           modifiedAdts = CFSwapInt64(modifiedAdts) >> 8
//           return Data(bytes:&modifiedAdts, count: 7)
//
//        modifiedAdts = 72041155050602496 | UInt64(frameLength + 7) << 13
//        modifiedAdts = CFSwapInt64(modifiedAdts) >> 8
//        return Data(bytes:&modifiedAdts, count: 7)
    
//        modifiedAdts = adts | UInt64(frameLength + 7) << 13
//        modifiedAdts = CFSwapInt64(modifiedAdts) >> 8
//        return Data(bytes:&modifiedAdts, count: 7)
}



/// gets called every time a buffer is needed
-(int) readIntoBuffer:(UInt8*)buffer withSize:(int)size
{
    NSLog(@"reading new audio packet!");
    
    
    int totalPacketSize = (int)CFReadStreamRead(stream, buffer, size);
    
    NSLog(@"total packet size %d", totalPacketSize);
    
    if(buffer == NULL) {
        NSLog(@"no data from socket. returning 0!");
        return 0;
    }
    
    
    // convert packet's type from [uint8] to NSData
    NSData *packetData = [NSData dataWithBytes:buffer length:totalPacketSize];
    // get the size of the data
    UInt32 dataSize;
    [packetData getBytes:&dataSize range:NSMakeRange(40, 4)];
    
    UInt64 timestamp;
    [packetData getBytes:&timestamp range:NSMakeRange(32, 8)];
    
    if(timestamp < lastTimeStamp) {
        NSLog(@"timestamp smaller! returning 0");
        return 0;
    }
    
    NSLog(@"%@", @(timestamp));
    
    lastTimeStamp = timestamp;
    // set the packet data again. The last line removed it
//    packetData = [NSMutableData dataWithBytesNoCopy:buffer length:totalPacketSize];
    
    // take the audio data
    NSData *audioData = [packetData subdataWithRange:NSMakeRange(44, dataSize)];
    // get buffer[40...44] and to Uint32LE
    
    
    [self buildHeader:dataSize];
    
    // build a new data to join the adts header with the packet
    packetWithHeader = [NSMutableData data];
    
    // append the adts header
    [packetWithHeader appendBytes:[adtsHeader mutableBytes] length:7];
    [packetWithHeader appendBytes:[audioData bytes] length:dataSize];

    memcpy(buffer, packetWithHeader.bytes, packetWithHeader.length);
    int retval = 7 + dataSize;
    
    //        }
    
    if (retval > 0)
    {
        position += totalPacketSize;
    }
    else
    {
        
        NSNumber* property = (__bridge_transfer NSNumber*)CFReadStreamCopyProperty(stream, kCFStreamPropertyFileCurrentOffset);
        
        position = property.longLongValue;
    }
    
    return retval;
}


-(void) seekToOffset:(SInt64)offset
{
    CFStreamStatus status = kCFStreamStatusClosed;
    
    if (stream != 0)
    {
        status = CFReadStreamGetStatus(stream);
    }
    
    BOOL reopened = NO;
    
    if (status == kCFStreamStatusAtEnd || status == kCFStreamStatusClosed || status == kCFStreamStatusError)
    {
        reopened = YES;
        
        [self close];
        [self open];
    }
    
    if (stream == 0)
    {
        CFRunLoopPerformBlock(eventsRunLoop.getCFRunLoop, NSRunLoopCommonModes, ^
                              {
                                  [self errorOccured];
                              });
        
        CFRunLoopWakeUp(eventsRunLoop.getCFRunLoop);
        
        return;
    }
    
    if (CFReadStreamSetProperty(stream, kCFStreamPropertyFileCurrentOffset, (__bridge CFTypeRef)[NSNumber numberWithLongLong:offset]) != TRUE)
    {
        position = 0;
    }
    else
    {
        position = offset;
    }
    
    if (!reopened)
    {
        CFRunLoopPerformBlock(eventsRunLoop.getCFRunLoop, NSRunLoopCommonModes, ^
                              {
                                  if ([self hasBytesAvailable])
                                  {
                                      [self dataAvailable];
                                  }
                              });
        
        CFRunLoopWakeUp(eventsRunLoop.getCFRunLoop);
    }
}

-(NSString*) description
{
    return [NSString stringWithFormat:@"StreamDataSource"];
}

-(BOOL) isAudioPacket: (UInt8*)buffer
{
    return buffer[11] == 1;
}

@end
