//
//  AudioFileWriter.m
//  SineGen
//
//  Created by uriadmin on 6/20/13.
//  Copyright (c) 2013 New York University. All rights reserved.
//

#import "AudioFileWriter.h"
#import "AudioPlayer.h"

@interface AudioFileWriter ()

@property (assign, nonatomic) ExtAudioFileRef fileRef;
@property (assign, nonatomic) AudioStreamBasicDescription format;
@property (assign, nonatomic) AudioBufferList *audioData;
@property (assign, nonatomic) UInt32 bufferSize;
@property (assign, nonatomic) BOOL isFinished;
@property (assign, nonatomic) Float32 *zeroBuffer;
@property (strong, nonatomic) NSString *fullFileName;
@property (assign, nonatomic) Float64 srate;
@property (assign, nonatomic) UInt32 numChannels;
@property (strong, nonatomic) NSLock *myLock;

@end

@implementation AudioFileWriter


- (NSString *) applicationDocumentsDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    return basePath;
}

void AUM_printAvailableStreamFormatsForId(AudioFileTypeID fileTypeID, UInt32 mFormatID)
{
    AudioFileTypeAndFormatID fileTypeAndFormat;
    fileTypeAndFormat.mFileType = fileTypeID;
    fileTypeAndFormat.mFormatID = mFormatID;
    UInt32 fileTypeIDChar = CFSwapInt32HostToBig(fileTypeID);
    UInt32 mFormatChar = CFSwapInt32HostToBig(mFormatID);
    
    OSStatus audioErr = noErr;
    UInt32 infoSize = 0;
    audioErr = AudioFileGetGlobalInfoSize(kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat,
                                          sizeof (fileTypeAndFormat),
                                          &fileTypeAndFormat,
                                          &infoSize);
    if (audioErr != noErr) {
        UInt32 format4cc = CFSwapInt32HostToBig(audioErr);
        NSLog(@"-: fileTypeID: %4.4s, mFormatId: %4.4s, not supported (%4.4s)",
              //i,
              (char*)&fileTypeIDChar,
              (char*)&mFormatChar,
              (char*)&format4cc
              );
        
        return;
    }
    
    AudioStreamBasicDescription *asbds = malloc (infoSize);
    audioErr = AudioFileGetGlobalInfo(kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat,
                                      sizeof (fileTypeAndFormat),
                                      &fileTypeAndFormat,
                                      &infoSize,
                                      asbds);
    if (audioErr != noErr) {
        UInt32 format4cc = CFSwapInt32HostToBig(audioErr);
        NSLog(@"-: fileTypeID: %4.4s, mFormatId: %4.4s, not supported (%4.4s)",
              //i,
              (char*)&fileTypeIDChar,
              (char*)&mFormatChar,
              (char*)&format4cc
              );
        
        return;
    }
    
    int asbdCount = infoSize / sizeof (AudioStreamBasicDescription);
    for (int i=0; i<asbdCount; i++) {
        UInt32 format4cc = CFSwapInt32HostToBig(asbds[i].mFormatID);
        
        NSLog(@"%d: fileTypeID: %4.4s, mFormatId: %4.4s, mFormatFlags: %ld, mBitsPerChannel: %ld",
              i,
              (char*)&fileTypeIDChar,
              (char*)&format4cc,
              asbds[i].mFormatFlags,
              asbds[i].mBitsPerChannel);
    }
    
    free (asbds);
}

void mainy (void)
{
    NSLog(@"********* CAF ***********");
    AUM_printAvailableStreamFormatsForId(kAudioFileCAFType, kAudioFormatAppleIMA4);
    AUM_printAvailableStreamFormatsForId(kAudioFileCAFType, kAudioFormatAC3);
    AUM_printAvailableStreamFormatsForId(kAudioFileCAFType, kAudioFormatMPEG4AAC);
    AUM_printAvailableStreamFormatsForId(kAudioFileCAFType, kAudioFormatAppleLossless);
    
    NSLog(@"********* AIFF ***********");
    AUM_printAvailableStreamFormatsForId(kAudioFileAIFFType, kAudioFormatLinearPCM);
    AUM_printAvailableStreamFormatsForId(kAudioFileAIFFType, kAudioFormatAppleIMA4);
    AUM_printAvailableStreamFormatsForId(kAudioFileAIFFType, kAudioFormatAC3);
    AUM_printAvailableStreamFormatsForId(kAudioFileAIFFType, kAudioFormatMPEG4AAC);
    AUM_printAvailableStreamFormatsForId(kAudioFileAIFFType, kAudioFormatAppleLossless);
    
    NSLog(@"********* M4A ***********");
    AUM_printAvailableStreamFormatsForId(kAudioFileM4AType, kAudioFormatAppleIMA4);
    AUM_printAvailableStreamFormatsForId(kAudioFileM4AType, kAudioFormatAC3);
    AUM_printAvailableStreamFormatsForId(kAudioFileM4AType, kAudioFormatMPEG4AAC);
    AUM_printAvailableStreamFormatsForId(kAudioFileM4AType, kAudioFormatAppleLossless);
    
    NSLog(@"********* AAC_ADTS ***********");
    AUM_printAvailableStreamFormatsForId(kAudioFileAAC_ADTSType, kAudioFormatLinearPCM);
    AUM_printAvailableStreamFormatsForId(kAudioFileAAC_ADTSType, kAudioFormatAppleIMA4);
    AUM_printAvailableStreamFormatsForId(kAudioFileAAC_ADTSType, kAudioFormatAC3);
    AUM_printAvailableStreamFormatsForId(kAudioFileAAC_ADTSType, kAudioFormatMPEG4AAC);
    AUM_printAvailableStreamFormatsForId(kAudioFileAAC_ADTSType, kAudioFormatAppleLossless);
    
    NSLog(@"********* AIFC ***********");
    AUM_printAvailableStreamFormatsForId(kAudioFileAIFCType, kAudioFormatLinearPCM);
    AUM_printAvailableStreamFormatsForId(kAudioFileAIFCType, kAudioFormatAppleIMA4);
    AUM_printAvailableStreamFormatsForId(kAudioFileAIFCType, kAudioFormatAC3);
    AUM_printAvailableStreamFormatsForId(kAudioFileAIFCType, kAudioFormatMPEG4AAC);
    AUM_printAvailableStreamFormatsForId(kAudioFileAIFCType, kAudioFormatAppleLossless);
}

- (void)openFileForPCMWriting {
    
//    mainy();
    
    // Get full path to the new output file
    NSString *filePath = [NSString pathWithComponents:@[[self applicationDocumentsDirectory], self.fullFileName]];
    CFURLRef outputFileURL = (__bridge CFURLRef)[NSURL fileURLWithPath: filePath];;
    
    // Write PCM, Float32 format
//    _format.mFormatID = kAudioFormatLinearPCM;
//    _format.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
//    _format.mChannelsPerFrame = self.numChannels;
//	_format.mBitsPerChannel = sizeof(Float32) * 8;
//	_format.mBytesPerFrame = _format.mChannelsPerFrame * sizeof(Float32);
//	_format.mFramesPerPacket = 1;
//	_format.mBytesPerPacket = _format.mFramesPerPacket * _format.mBytesPerFrame;
//    _format.mSampleRate = self.srate;
    
    _format.mFormatID = kAudioFormatLinearPCM;
    _format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    _format.mChannelsPerFrame = self.numChannels;
	_format.mBitsPerChannel = sizeof(SInt16) * 8;
	_format.mBytesPerFrame = _format.mChannelsPerFrame * sizeof(SInt16);
	_format.mFramesPerPacket = 1;
	_format.mBytesPerPacket = _format.mFramesPerPacket * _format.mBytesPerFrame;
    _format.mSampleRate = self.srate;
    
    // Open output file for writing
    CheckError(ExtAudioFileCreateWithURL(outputFileURL,
                                         kAudioFileWAVEType,
                                         &_format,
                                         NULL,
                                         kAudioFileFlags_EraseFile,
                                         &_fileRef),
               "ExtAudioFileCreateWithURL failed");
    
    // Buffer size will be 0 until samples are read
    self.bufferSize = 0;
    
    self.isClosed = NO;
}

- (void)loadFileWithName:(NSString*)fullFileName
              sampleRate:(Float64)srate
          andNumChannels:(UInt32)numChannels {
    
    self.myLock = [NSLock new];
    
    assert(numChannels == 1 || numChannels == 2);
    
    self.fullFileName = fullFileName;
    self.srate = srate;
    self.numChannels = numChannels;
    
    // Opens the file and sets the correct format for reading
    [self openFileForPCMWriting];
    
    // File is not finished
    self.isFinished = NO;
}

- (void)writeSamplesWithBuffer:(Float32*)buffer andBufferSize:(UInt32)bufferSize {
    
    if (self.isClosed) {
        return;
    }
    
    // Lock process for threading
    [self.myLock lock];
    
    // Compute the buffer size in bytes
    UInt32 byteBufferSize = bufferSize * _format.mBytesPerPacket;
    
    // If the buffer size was not set, we have to set it
    //      (first time we call this function, or buffersize changed)
    if (self.bufferSize != byteBufferSize) {
        // Reserve memory for the buffer
        // UInt8 *outputBuffer = (UInt8 *)malloc(sizeof(UInt8) * byteBufferSize);
        _audioData = (AudioBufferList*)(calloc(1, offsetof(AudioBufferList, mBuffers) + (sizeof(AudioBuffer))));
        
        // Interleaved audio (all samples in one buffer)
        _audioData->mNumberBuffers = 1;
        
        // Set up audio buffer
        _audioData->mBuffers[0].mNumberChannels = _format.mChannelsPerFrame;
        _audioData->mBuffers[0].mDataByteSize = byteBufferSize;
        _audioData->mBuffers[0].mData = (SInt16*)malloc(sizeof(SInt16) * bufferSize * _format.mChannelsPerFrame);
        
        // Store the size of the buffer
        self.bufferSize = byteBufferSize;
    }
    
    // Copy data and convert from Float32 to SInt16
    SInt16 *outBuffer = (SInt16*)_audioData->mBuffers[0].mData;
    for (NSUInteger i = 0; i < bufferSize; i++) {
        outBuffer[_format.mChannelsPerFrame*i] = (SInt16)(buffer[_format.mChannelsPerFrame*i] * SHRT_MAX);
        if (_format.mChannelsPerFrame == 2) {
            outBuffer[_format.mChannelsPerFrame*i + 1] = (SInt16)(buffer[_format.mChannelsPerFrame*i+1] * SHRT_MAX);
        }
    }
    
    // Write the actual audio data
    CheckError(ExtAudioFileWrite(_fileRef, bufferSize, _audioData), "ExtAudioFileWrite failed");
    
    // Unlock process
    [self.myLock unlock];
}

- (void)closeFile {
    if (!self.isClosed) {
        [self.myLock lock];
        
        CheckError(ExtAudioFileDispose(_fileRef), "ExtAudioFileWrite failed");
        self.isClosed = YES;
        self.bufferSize = 0;
        free(_audioData->mBuffers[0].mData);
        free(_audioData);
        
        [self.myLock unlock];
        
        self.myLock = nil;
    }
}
@end
