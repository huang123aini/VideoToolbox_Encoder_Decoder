//
//  HDEncoder.m
//  VideoToolBox_Encoder_Decoder
//
//  Created by 黄世平 on 2021/8/28.
//

#import "HDEncoder.h"

@interface HDEncoder()

-(void)invalidSession;

@end

@implementation HDEncoder

-(instancetype)initWithEncoderConfig:(EncoderConfig)config {
    if (self = [super init]) {
        _width = config.width;
        _height = config.height;
        _gop = config.gop;
        _wantFps = config.wantFps;
        _bitRate = config.bitRate;
        _bitRateLimit = config.bitRateLimit;
        /**
         *编码队列
         */
        _encodeQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    }
    return self;
}

-(void)startEncoder {
    dispatch_sync(_encodeQueue  , ^{
        _frameNum = 0;
        OSStatus status = VTCompressionSessionCreate(NULL, _width, _height, kCMVideoCodecType_H264, NULL, NULL, NULL, compressH264Done, (__bridge void *)(self),  &_encodingSession);
        NSLog(@"H264: VTCompressionSessionCreate %d", (int)status);
        if (status != 0)
        {
            NSLog(@"H264: Unable to create a H264 session");
            return ;
        }
        /**
         *设置实时编码输出（避免延迟）
         */
        VTSessionSetProperty(_encodingSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        VTSessionSetProperty(_encodingSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
        /**
         *设置gop
         */
        CFNumberRef  frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &_gop);
        VTSessionSetProperty(_encodingSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, frameIntervalRef);
        
        /**
         *设置期望帧率
         */
        CFNumberRef  fpsRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &_wantFps);
        VTSessionSetProperty(_encodingSession, kVTCompressionPropertyKey_ExpectedFrameRate, fpsRef);
        
        /**
         *设置编码码率
         */
        CFNumberRef bitRateRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &_bitRate);
        VTSessionSetProperty(_encodingSession, kVTCompressionPropertyKey_AverageBitRate, bitRateRef);
        
        /**
         *码率上限值
         */
        CFNumberRef bitRateLimitRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &_bitRateLimit);
        VTSessionSetProperty(_encodingSession, kVTCompressionPropertyKey_DataRateLimits, bitRateLimitRef);
        
        /**
         *开启编码
         */
        VTCompressionSessionPrepareToEncodeFrames(_encodingSession);
    });
}

-(void)encoder:(CMSampleBufferRef)samplebuffer {
    CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(samplebuffer);
    /**
     *帧时间
     */
    CMTime presentationTimeStamp = CMTimeMake(_frameNum++, 1000);
    VTEncodeInfoFlags flags;
    OSStatus statusCode = VTCompressionSessionEncodeFrame(_encodingSession,
                                                          imageBuffer,
                                                          presentationTimeStamp,
                                                          kCMTimeInvalid,
                                                          NULL, NULL, &flags);
    if (statusCode != noErr) {
        NSLog(@"H264: VTCompressionSessionEncodeFrame failed with %d", (int)statusCode);
        [self invalidSession];
        return;
    }
}

-(void)invalidSession {
    VTCompressionSessionInvalidate(_encodingSession);
    CFRelease(_encodingSession);
    _encodingSession = NULL;
}

// 编码完成回调
void compressH264Done(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer) {
    NSLog(@"compressH264Done called with status %d infoFlags %d", (int)status, (int)infoFlags);
    if (status != 0) {
        return;
    }
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        NSLog(@"didCompressH264 data is not ready ");
        return;
    }
    HDEncoder* encoder = (__bridge HDEncoder*)outputCallbackRefCon;
    /**
     *判断当前帧是否为关键帧
     */
    bool keyframe = !CFDictionaryContainsKey( (CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0)), kCMSampleAttachmentKey_NotSync);
    
    /*
     *获取sps & pps数据
     */
    if (keyframe) {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        size_t sparameterSetSize, sparameterSetCount;
        const uint8_t *sparameterSet;
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0 );
        if (statusCode == noErr) {
            /**
             *获得了sps，再获取pps
             */
            size_t pparameterSetSize, pparameterSetCount;
            const uint8_t *pparameterSet;
            OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0 );
            if (statusCode == noErr) {
                /*
                 *获取SPS和PPS data
                 */
                NSData *sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
                NSData *pps = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];
                if (encoder) {
                    [encoder gotSpsPps:sps pps:pps];
                }
            }
        }
    }
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    
    /**
     *这里获取了数据指针，和NALU的帧总长度，前四个字节里面保存
     */
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr) {
        size_t bufferOffset = 0;
        /**
         *返回的nalu数据前四个字节不是0001的startcode，而是大端模式的帧长度length
         */
        static const int AVCCHeaderLength = 4;
        
        /**
         *循环获取nalu数据
         */
        while (bufferOffset < totalLength - AVCCHeaderLength) {
            uint32_t NALUnitLength = 0;
            /**
             *读取NALU长度的数据
             */
            memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength);
            /**
             *从大端转系统端
             */
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            
            NSData* data = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset + AVCCHeaderLength) length:NALUnitLength];
            [encoder gotEncodedData:data];
            /**
             *移动到下一个NALU单元
             */
            bufferOffset += AVCCHeaderLength + NALUnitLength;
        }
    }
    
}

/**
 *填充SPS和PPS数据
 */
- (void)gotSpsPps:(NSData*)sps pps:(NSData*)pps {
    NSLog(@"gotSpsPps %d %d", (int)[sps length], (int)[pps length]);
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1; //string literals have implicit trailing '\0'
    NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
    if (self.encodeDataDelegate) {
        [self.encodeDataDelegate encodeData:ByteHeader];
        [self.encodeDataDelegate encodeData:sps];
        [self.encodeDataDelegate encodeData:ByteHeader];
        [self.encodeDataDelegate encodeData:pps];
    }
 
}

/**
 *填充NALU数据
 */
- (void)gotEncodedData:(NSData*)data {
    NSLog(@"gotEncodedData %d", (int)[data length]);
    if (self.encodeDataDelegate) {
        const char bytes[] = "\x00\x00\x00\x01";
        size_t length = (sizeof bytes) - 1; //string literals have implicit trailing '\0'
        NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
        [self.encodeDataDelegate encodeData:ByteHeader];
        [self.encodeDataDelegate encodeData:data];
    }
}

- (void)stopEncoder {
    VTCompressionSessionCompleteFrames(_encodingSession, kCMTimeInvalid);
    VTCompressionSessionInvalidate(_encodingSession);
    CFRelease(_encodingSession);
    _encodingSession = NULL;
}


-(void)setEncodeDataDelegate:(id _Nonnull)encodeDataDelegate {
    self.encodeDataDelegate = encodeDataDelegate;
}
@end
