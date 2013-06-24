//
//  AudioFileWriter.h
//  SineGen
//
//  Created by uriadmin on 6/20/13.
//  Copyright (c) 2013 New York University. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

@interface AudioFileWriter : NSObject

@property (assign, nonatomic) BOOL isClosed;

- (void)loadFileWithName:(NSString*)fullFileName
              sampleRate:(Float64)srate
          andNumChannels:(UInt32)numChannels;

- (void)writeSamplesWithBuffer:(Float32*)buffer andBufferSize:(UInt32)bufferSize;
- (void)closeFile;

@end
