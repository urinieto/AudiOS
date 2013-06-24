//
//  AudioFileReader.h
//  SineGen
//
//  Created by Uri Nieto on 6/18/13.
//  Copyright (c) 2013 New York University. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

@interface AudioFileReader : NSObject

@property (assign, nonatomic) NSUInteger numChannels;
@property (assign, nonatomic, setter = setRepeatOn:) BOOL isRepeatOn;

- (void)loadFileWithName:(NSString*)fullFileName andSampleRate:(Float64)srate;
- (Float32*)readSamplesWithBufferSize:(UInt32)bufferSize;

@end
