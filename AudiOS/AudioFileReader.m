//
//  AudioFileReader.m
//  SineGen
//
//  Created by Uri Nieto on 6/18/13.
//  Copyright (c) 2013 New York University. All rights reserved.
//

#import "AudioFileReader.h"
#import "AudioPlayer.h"

@interface AudioFileReader ()

@property (assign, nonatomic) ExtAudioFileRef fileRef;
@property (assign, nonatomic) AudioStreamBasicDescription format;
@property (assign, nonatomic) AudioBufferList audioData;
@property (assign, nonatomic) UInt32 bufferSize;
@property (assign, nonatomic) BOOL isFinished;
@property (assign, nonatomic) Float32 *zeroBuffer;
@property (strong, nonatomic) NSString *fullFileName;
@property (assign, nonatomic) Float64 srate;
@property (assign, nonatomic) BOOL isFirstOpen;

@end

@implementation AudioFileReader

- (NSUInteger)numChannels {
    return self.format.mChannelsPerFrame;
}

- (void)openFileForPCMReading {
    
    // Get full path to the file
    NSString* fileName = [[self.fullFileName lastPathComponent] stringByDeletingPathExtension];
    NSString* extension = [self.fullFileName pathExtension];
    NSString* filePath = [[NSBundle mainBundle] pathForResource:fileName
                                                         ofType:extension];
    CFURLRef inputFileURL = (__bridge CFURLRef)[NSURL fileURLWithPath: filePath];
    
    // Open input file
    CheckError(ExtAudioFileOpenURL(inputFileURL, &_fileRef), "ExtAudioFileOpenURL failed");
    
    // Read input file format (we will store the number of channels)
    UInt32 srcFormatSize = sizeof(_format);
    CheckError(ExtAudioFileGetProperty(_fileRef, kExtAudioFileProperty_FileDataFormat, &srcFormatSize,
                                       &_format), "Couldn't get input audio format");
    
    // Force to read a PCM, Float32 format
    _format.mFormatID = kAudioFormatLinearPCM;
    _format.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
    //    _format.mChannelsPerFrame = 1; // Number of Channels is automatically set unless this is uncommented
	_format.mBitsPerChannel = sizeof(Float32) * 8;
	_format.mBytesPerFrame = _format.mChannelsPerFrame * sizeof(Float32);
	_format.mFramesPerPacket = 1;
	_format.mBytesPerPacket = _format.mFramesPerPacket * _format.mBytesPerFrame;
    _format.mSampleRate = self.srate;
    
    // Set the new format
    CheckError(ExtAudioFileSetProperty(_fileRef,
                                       kExtAudioFileProperty_ClientDataFormat,
                                       sizeof (AudioStreamBasicDescription),
                                       &_format),
               "Couldn't set client data format on input ext file");
    
    // Buffer size will be 0 until samples are read
    self.bufferSize = 0;
}

- (void)loadFileWithName:(NSString*)fullFileName andSampleRate:(Float64)srate {
    
    self.fullFileName = fullFileName;
    self.srate = srate;
    
    // Opens the file and sets the correct format for reading
    [self openFileForPCMReading];
    
    // Do not repeat by default
    self.isRepeatOn = NO;
    
    // File is not finished
    self.isFinished = NO;
    
    // It's the first time we open the file
    self.isFirstOpen = YES;
}

- (Float32*)readSamplesWithBufferSize:(UInt32)bufferSize {
    
    if (self.isFinished && !self.isRepeatOn) {
        return _zeroBuffer;
    }
    
    // Compute the buffer size in bytes
    UInt32 byteBufferSize = bufferSize * _format.mBytesPerPacket;
    
    // If the buffer size was not set, we have to set it
    //      (first time we call this function, or buffersize changed)
    if (self.bufferSize != byteBufferSize) {
        // Release memory if it's not the first time
        if (!self.isFirstOpen) {
            free(_audioData.mBuffers[0].mData);
        }
        else {
            // Create and store zero buffer
            _zeroBuffer = (Float32 *)malloc(sizeof(UInt8) * byteBufferSize);
            memset(_zeroBuffer, 0, sizeof(UInt8) * byteBufferSize);
        }
        
        // Reserve memory for the buffer
        UInt8 *outputBuffer = (UInt8 *)malloc(sizeof(UInt8) * byteBufferSize);
        
        // Interleaved audio (all samples in one buffer)
        _audioData.mNumberBuffers = 1;
        
        // Set up audio buffer
        _audioData.mBuffers[0].mNumberChannels = _format.mChannelsPerFrame;
        _audioData.mBuffers[0].mDataByteSize = byteBufferSize;
        _audioData.mBuffers[0].mData = outputBuffer;
        
        // Store the size of the buffer
        self.bufferSize = byteBufferSize;
        
        // Not first time from now on
        self.isFirstOpen = NO;
    }
    
    // Number of frames to read
    // One frame contains N samples corresponding to N channels
    UInt32 frameCount = bufferSize; // We don't want to overwrite bufferSize
    
    // Read the actual audio data
    CheckError(ExtAudioFileRead(_fileRef, &frameCount, &_audioData), "ExtAudioFileRead failed");
    
    // Check if we are done reading
    if (frameCount < bufferSize) {
        self.isFinished = YES;
        
        if (self.isRepeatOn) {
            // Unfortunately ExtAudioFileSeek doesn't work here because ExtAudioFileRead
            // automatically closes the file when it's done reading. So we have to reopen it.
//            CheckError(ExtAudioFileSeek(_fileRef, 0), "ExtAudioFileSeek failed");
            CheckError(ExtAudioFileDispose(_fileRef), "ExtAudioFileDispose failed");
            [self openFileForPCMReading];
            self.isFinished = NO;
        }
        
    }
    
    // Return audio data
    return (Float32*)_audioData.mBuffers[0].mData;
}


@end
