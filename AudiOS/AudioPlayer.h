//
//  AudioPlayer.h
//
//  Created by Uri Nieto on 6/17/13.
//  Copyright (c) 2013 New York University. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

// Callback function prototype
typedef void (* AudioPlayerCallback)( Float32 * buffer, UInt32 numFrames, void * userData );


@interface AudioPlayer : NSObject

void CheckError(OSStatus error, const char *operation);
void convertFromUser( AudioBufferList * inData, Float32 * buffy, UInt32 numFrames, NSUInteger numChannels );

- (id)initWithSampleRate:(Float64)srate
               frameSize:(UInt32)frameSize
          andNumChannels:(UInt32)numChannels;

- (void)startWithCallback:(AudioPlayerCallback)callback
              andUserData:(void*)userData;

@end
