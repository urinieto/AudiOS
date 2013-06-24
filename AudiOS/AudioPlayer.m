//
//  AudioPlayer.m
//
//  Created by Uri Nieto on 6/17/13.
//  Copyright (c) 2013 New York University. All rights reserved.
//
// Based on some code from:
// - Learning Core Audio Book by Adamson & Avila
// - MoMu Library: http://momu.stanford.edu/

#import "AudioPlayer.h"

#define kMaxFrameSize 4096

@interface StateData : NSObject {
@public
    AudioUnit rioUnit;
    Float32 *ioBuffer;
    AudioPlayerCallback callback;
}

@property (assign) AudioStreamBasicDescription asbd;
@property (assign) Float64 srate;
@property (assign) UInt32 frameSize;
@property (assign) UInt32 numChannels;
@property (assign) void *userData;

@end

@implementation StateData

// Empty: properties do the work for us.

@end


@interface AudioPlayer ()

@property (strong, nonatomic) StateData *stateData;

@end

@implementation AudioPlayer


#pragma mark helpers
// generic error handler - if err is nonzero, prints error message and exits program.
void CheckError(OSStatus error, const char *operation)
{
	if (error == noErr) return;
	
	char str[20];
	// see if it appears to be a 4-char-code
	*(UInt32 *)(str + 1) = CFSwapInt32HostToBig(error);
	if (isprint(str[1]) && isprint(str[2]) && isprint(str[3]) && isprint(str[4])) {
		str[0] = str[5] = '\'';
		str[6] = '\0';
	} else
		// no, format it as an integer
		sprintf(str, "%d", (int)error);
    
	fprintf(stderr, "Error: %s (%s)\n", operation, str);
    
	exit(1);
}

#pragma mark callbacks
static void MyInterruptionListener (void *inUserData,
                                    UInt32 inInterruptionState) {
	
	printf ("Interrupted! inInterruptionState=%ld\n", inInterruptionState);
    AudioPlayer *userPlayer = (__bridge AudioPlayer *)(inUserData);
	switch (inInterruptionState) {
		case kAudioSessionBeginInterruption:
			break;
		case kAudioSessionEndInterruption:
			// TODO: doesn't work!
			CheckError(AudioSessionSetActive(true),
					   "Couldn't set audio session active");
			CheckError(AudioUnitInitialize(userPlayer.stateData->rioUnit),
					   "Couldn't initialize RIO unit");
			CheckError (AudioOutputUnitStart (userPlayer.stateData->rioUnit),
						"Couldn't start RIO unit");
			break;
		default:
			break;
	};
}

static void rerouteAudio() {
    // Override Audio Route to make it sound through the speaker (instead of the receiver) if
    // no headphones are plugged.
    CFStringRef route;
    UInt32 size = sizeof(CFStringRef);
    CheckError(AudioSessionGetProperty( kAudioSessionProperty_AudioRoute, &size, &route ),
               "couldn't get new audio route");
    UInt32 override;
    CFRange range = CFStringFind(route, CFSTR("Headphone"), 0);
    if(range.location != kCFNotFound)
        override = kAudioSessionOverrideAudioRoute_None;
    else
        override = kAudioSessionOverrideAudioRoute_Speaker;
    CheckError(AudioSessionSetProperty(kAudioSessionProperty_OverrideAudioRoute,
                                       sizeof(override),
                                       &override),
               "Couldn't override audio route");
}

static void propListener( void * inClientData, AudioSessionPropertyID inID,
                         UInt32 inDataSize, const void * inData ) {
    if( inID != kAudioSessionProperty_AudioRouteChange ) {
        return;
    }
    
    // Reroute Audio if needed
    rerouteAudio();
}

//-----------------------------------------------------------------------------
// name: convertToUser()
// desc: convert to user data (stereo)
// (similar to MoMu library)
//-----------------------------------------------------------------------------
void convertToUser( AudioBufferList * inData, Float32 *buffy, UInt32 numFrames, NSUInteger numChannels, UInt32 *actualFrames ) {

    // get number of frames
    UInt32 inFrames = inData->mBuffers[0].mDataByteSize / sizeof(SInt32);
    // make sure  space
    assert( inFrames <= numFrames );
    // channels
    SInt32 * left = (SInt32 *)inData->mBuffers[0].mData;
    SInt32 * right = NULL;
    if (numChannels == 2)
        right = (SInt32 *)inData->mBuffers[1].mData;
    // fixed to float scaling factor
    Float32 factor = (Float32)(1 << 24);
    // interleave (AU is by default non interleaved)
    for( NSUInteger i = 0; i < inFrames; i++ )
    {
        // convert (AU is by default 8.24 fixed)
        buffy[numChannels*i] = ((Float32)left[i]) / factor;
        if (numChannels == 2)
            buffy[numChannels*i+1] = ((Float32)right[i]) / factor;
    }
    // return
    *actualFrames = inFrames;
}




//-----------------------------------------------------------------------------
// name: convertFromUser()
// desc: convert from user data (stereo)
// (similar to MoMu library)
//-----------------------------------------------------------------------------
void convertFromUser( AudioBufferList * inData, Float32 * buffy, UInt32 numFrames, NSUInteger numChannels ) {
    
    // get number of frames
    UInt32 inFrames = inData->mBuffers[0].mDataByteSize / 4;
    // make sure enough space
    assert( inFrames <= numFrames );
    // channels
    SInt32 * left = (SInt32 *)inData->mBuffers[0].mData;
    SInt32 * right = NULL;
    if (numChannels == 2)
        right = (SInt32 *)inData->mBuffers[1].mData;
    // fixed to float scaling factor
    Float32 factor = (Float32)(1 << 24);
    // interleave (AU is by default non interleaved)
    for( NSUInteger i = 0; i < inFrames; i++ )
    {
        // convert (AU is by default 8.24 fixed)
        left[i] = (SInt32)(buffy[numChannels*i] * factor);
        if (numChannels == 2)
            right[i] = (SInt32)(buffy[numChannels*i+1] * factor);
    }
}

static OSStatus InputRenderCallback(
                           void *							inRefCon,
                           AudioUnitRenderActionFlags *     ioActionFlags,
                           const AudioTimeStamp *			inTimeStamp,
                           UInt32							inBusNumber,
                           UInt32							inNumberFrames,
                           AudioBufferList *				ioData) {
    
    StateData *stateData = (__bridge StateData *)(inRefCon);
    
	// just copy samples
	UInt32 bus1 = 1;
	CheckError(AudioUnitRender(stateData->rioUnit, ioActionFlags,
                               inTimeStamp, bus1,
                               inNumberFrames, ioData),
			   "Couldn't render from RemoteIO unit");
    
    // actual frames
    UInt32 actualFrames = 0;
    
    // convert
    convertToUser(ioData, stateData->ioBuffer, stateData.frameSize,
                  stateData.numChannels, &actualFrames);
    
    // callback
    stateData->callback(stateData->ioBuffer, actualFrames, stateData.userData);
    
    // convert back
    convertFromUser(ioData, stateData->ioBuffer,
                    stateData.frameSize, stateData.numChannels);
	
	return noErr;
}

// Lazy Instantiation
- (StateData*)stateData {
    if (!_stateData) {
        _stateData = [[StateData alloc] init];
        _stateData->ioBuffer = (Float32*)malloc(2 * kMaxFrameSize * sizeof(Float32));
    }
    return _stateData;
}

- (void)setupAudioWithSampleRate:(Float64)srate
                       frameSize:(UInt32)frameSize
                  andNumChannels:(UInt32)numChannels {
    // set up audio session
    CheckError(AudioSessionInitialize(NULL,
                                      kCFRunLoopDefaultMode,
                                      MyInterruptionListener,
                                      (__bridge void *)(self)),
               "couldn't initialize audio session");
    
	UInt32 category = kAudioSessionCategory_PlayAndRecord;
    CheckError(AudioSessionSetProperty(kAudioSessionProperty_AudioCategory,
                                       sizeof(category),
                                       &category),
               "Couldn't set category on audio session");
    
    // set property listener
    CheckError(AudioSessionAddPropertyListener( kAudioSessionProperty_AudioRouteChange, propListener, NULL ),
               "couldn't set property listener");
    
    // Reroute audio if needed
    rerouteAudio();
    
	// is audio input available?
	UInt32 ui32PropertySize = sizeof (UInt32);
	UInt32 inputAvailable;
	CheckError(AudioSessionGetProperty(kAudioSessionProperty_AudioInputAvailable,
                                       &ui32PropertySize,
                                       &inputAvailable),
			   "Couldn't get current audio input available prop");
	if (! inputAvailable) {
		NSLog(@"Warinign: Input for audio is not available");
	}
    
	// inspect the hardware input rate
	Float64 hardwareSampleRate;
	UInt32 propSize = sizeof (hardwareSampleRate);
	CheckError(AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareSampleRate,
									   &propSize,
									   &hardwareSampleRate),
			   "Couldn't get hardwareSampleRate");
    
    if (srate > hardwareSampleRate) {
        NSLog(@"Warnign: Maximum sampling rate is %f.", hardwareSampleRate);
    }
    if (frameSize > kMaxFrameSize) {
        NSLog(@"Warning: Maximum audio frame size is %d.", kMaxFrameSize);
    }
    
	// describe unit
	AudioComponentDescription audioCompDesc;
	audioCompDesc.componentType = kAudioUnitType_Output;
	audioCompDesc.componentSubType = kAudioUnitSubType_RemoteIO;
	audioCompDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
	audioCompDesc.componentFlags = 0;
	audioCompDesc.componentFlagsMask = 0;
	
	// get rio unit from audio component manager
	AudioComponent rioComponent = AudioComponentFindNext(NULL, &audioCompDesc);
	CheckError(AudioComponentInstanceNew(rioComponent, &self.stateData->rioUnit),
			   "Couldn't get RIO unit instance");
	
	// set up the rio unit for playback
	UInt32 oneFlag = 1;
	AudioUnitElement bus0 = 0;
	CheckError(AudioUnitSetProperty (self.stateData->rioUnit,
                                     kAudioOutputUnitProperty_EnableIO,
                                     kAudioUnitScope_Output,
                                     bus0,
                                     &oneFlag,
                                     sizeof(oneFlag)),
			   "Couldn't enable RIO output");
	
	// enable rio input
	AudioUnitElement bus1 = 1;
	CheckError(AudioUnitSetProperty(self.stateData->rioUnit,
									kAudioOutputUnitProperty_EnableIO,
									kAudioUnitScope_Input,
									bus1,
									&oneFlag,
									sizeof(oneFlag)),
			   "Couldn't enable RIO input");
    
	// setup an asbd in the iphone canonical format
	AudioStreamBasicDescription myASBD;
	memset (&myASBD, 0, sizeof (myASBD));
	myASBD.mSampleRate = srate;
	myASBD.mFormatID = kAudioFormatLinearPCM;
    //	myASBD.mFormatFlags = kAudioFormatFlagsCanonical; // SignedInteger | NativeEndian | FlagIsPacked
    myASBD.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked |
    kAudioFormatFlagIsNonInterleaved | (24 << kLinearPCMFormatFlagsSampleFractionShift);
    //    myASBD.mFormatFlags = kAudioFormatFlagIsSignedInteger;
	myASBD.mBytesPerPacket = 4;
    myASBD.mBytesPerFrame = 4;
	myASBD.mFramesPerPacket = 1;
	myASBD.mChannelsPerFrame = numChannels;
	myASBD.mBitsPerChannel = 32;
	
    // set format for output (bus 0) on rio's input scope
	CheckError(AudioUnitSetProperty (self.stateData->rioUnit,
                                     kAudioUnitProperty_StreamFormat,
                                     kAudioUnitScope_Input,
                                     bus0,
                                     &myASBD,
                                     sizeof (myASBD)),
			   "Couldn't set ASBD for RIO on input scope / bus 0");
	
	
	// set asbd for mic input
	CheckError(AudioUnitSetProperty (self.stateData->rioUnit,
                                     kAudioUnitProperty_StreamFormat,
                                     kAudioUnitScope_Output,
                                     bus1,
                                     &myASBD,
                                     sizeof (myASBD)),
			   "Couldn't set ASBD for RIO on output scope / bus 1");
	
    // Set state structure
	self.stateData.asbd = myASBD;
    self.stateData.srate = srate;
    self.stateData.frameSize = frameSize;
    self.stateData.numChannels = numChannels;
    
    // Set preferred sample rate
    CheckError(AudioSessionSetProperty( kAudioSessionProperty_PreferredHardwareSampleRate,
                                       sizeof(srate), &srate ),
               "Couldn't set preferred hardware sampling rate");
    
    // Set I/O Buffer Duration
    Float32 preferredBufferSize = (Float32)(frameSize / srate);
    CheckError(AudioSessionSetProperty( kAudioSessionProperty_PreferredHardwareIOBufferDuration,
                                       sizeof(preferredBufferSize), &preferredBufferSize ),
               "Couldn't set i/o buffer duration");
    
	
	// set callback method
	AURenderCallbackStruct callbackStruct;
	callbackStruct.inputProc = InputRenderCallback; // callback function
//	callbackStruct.inputProcRefCon = (void*)CFBridgingRetain(self.stateData);
    callbackStruct.inputProcRefCon = (__bridge void *)(self.stateData);
	
	CheckError(AudioUnitSetProperty(self.stateData->rioUnit,
                                    kAudioUnitProperty_SetRenderCallback,
                                    kAudioUnitScope_Global,
                                    bus0,
                                    &callbackStruct,
                                    sizeof (callbackStruct)),
			   "Couldn't set RIO render callback on bus 0");
    
    // Init Unit
    CheckError(AudioUnitInitialize(self.stateData->rioUnit),
			   "Couldn't initialize RIO unit");
}

- (id)initWithSampleRate:(Float64)srate
               frameSize:(UInt32)frameSize
          andNumChannels:(UInt32)numChannels {
    
    self = [super init];
    if (self) {
        [self setupAudioWithSampleRate:srate frameSize:frameSize andNumChannels:numChannels];
    }
    return self;
}

- (void)startWithCallback:(AudioPlayerCallback)callback
              andUserData:(void*)userData {
    
    // Activate Audio Session
    CheckError(AudioSessionSetActive(true),
               "Couldn't set AudioSession active");
    
    // Set callback
    self.stateData->callback = callback;
    
    // Set user data
    self.stateData.userData = userData;
    
    // Start remoteio unit
	CheckError (AudioOutputUnitStart (self.stateData->rioUnit),
				"Couldn't start RIO unit");
	
	printf("AudioPlayer started!\n");
}

@end
